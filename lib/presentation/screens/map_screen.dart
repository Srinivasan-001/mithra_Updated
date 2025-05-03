import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:logger/logger.dart';
import 'package:geocoding/geocoding.dart'; // For geocoding
import 'dart:math'; // For min/max

// TODO: Securely manage API Key - consider using environment variables or Flutter flavors
const String googleApiKey = "AIzaSyCq2s28kdJlvauO88jHCwqjW2vwrEAmsA8";

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Logger _logger = Logger();
  final Completer<GoogleMapController> _mapController = Completer();
  GoogleMapController? _googleMapController;
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _locationPermissionGranted = false;

  // Routing
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final List<LatLng> _polylineCoordinates = [];
  final PolylinePoints _polylinePoints = PolylinePoints();
  LatLng? _originPosition;
  LatLng? _destinationPosition;
  bool _useCurrentLocationAsOrigin = true;

  // Geocoding
  bool _isSearchingOrigin = false;
  bool _isSearchingDestination = false;
  String? _originAddress;
  String? _destinationAddress;

  // Hotspots
  final Set<Circle> _hotspotCircles = {};
  List<LatLng> _hotspots = []; // Placeholder for fetched hotspots
  bool _showHotspotsOnRoute = false;

  // Map Type
  MapType _currentMapType = MapType.normal;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962), // Default: Googleplex
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _fetchHotspots(); // Fetch hotspot data

    // Add listeners to text controllers
    _originController.addListener(() {
      if (_originPosition != null && _originController.text != _originAddress) {
        setState(() {
          _originPosition = null;
        });
      }
    });
    _destinationController.addListener(() {
      if (_destinationPosition != null &&
          _destinationController.text != _destinationAddress) {
        setState(() {
          _destinationPosition = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _originController.dispose();
    _destinationController.dispose();
    _googleMapController?.dispose();
    super.dispose();
  }

  // --- Hotspot Methods ---
  Future<void> _fetchHotspots() async {
    try {
      // TODO: Implement real Firebase/Firestore fetching logic
      // For now we're simulating with placeholder data
      await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      
      // Example hotspot data - in a real app this would come from Firestore
      final List<Map<String, dynamic>> hotspotData = [
        {'lat': 37.430, 'lng': -122.085, 'radius': 100, 'risk_level': 'high'},
        {'lat': 37.425, 'lng': -122.080, 'radius': 150, 'risk_level': 'medium'},
      ];
      
      if (mounted) {
        setState(() {
          _hotspots = hotspotData.map((data) => 
            LatLng(data['lat'] as double, data['lng'] as double)
          ).toList();
          _updateHotspotCircles();
        });
      }
      _logger.i("Fetched ${_hotspots.length} hotspots (placeholder data).");
    } catch (e) {
      _logger.e("Error fetching hotspots: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load safety data: $e")),
        );
      }
    }
  }

  void _updateHotspotCircles() {
    _hotspotCircles.clear();
    for (int i = 0; i < _hotspots.length; i++) {
      _hotspotCircles.add(
        Circle(
          circleId: CircleId('hotspot_$i'),
          center: _hotspots[i],
          radius: 100, // Example radius in meters
          fillColor: Colors.red.withAlpha(76), // Using withAlpha instead of withOpacity
          strokeColor: Colors.red,
          strokeWidth: 1,
        ),
      );
    }
    // No need to call setState here if called within another setState block
  }

  // --- Location & Map Methods ---
  Future<void> _requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied || status.isRestricted) {
      _logger.i('Requesting location permission...');
      status = await Permission.locationWhenInUse.request();
    }

    if (status.isGranted) {
      _logger.i('Location permission granted.');
      if (mounted) {
        setState(() {
          _locationPermissionGranted = true;
        });
      }
      _getCurrentLocationAndTrack();
    } else {
      _logger.w('Location permission denied. Status: $status');
      String message =
          status.isPermanentlyDenied
              ? 'Location permission permanently denied. Please enable it in app settings.'
              : 'Location permission is required for map features.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      setState(() {
        _locationPermissionGranted = false;
      });
    }
  }

  Future<Position?> _getLatestLocation() async {
    if (!_locationPermissionGranted) {
      _logger.w('Cannot get location: Permission not granted.');
      await _requestLocationPermission();
      if (!_locationPermissionGranted) return null;
    }
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position!.latitude, position.longitude);
        });
      }
      _logger.i('Fetched latest location: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');
      return position;
    } catch (e) {
      _logger.e("Error getting latest location: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get current location: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _getCurrentLocationAndTrack() async {
    Position? position = await _getLatestLocation();
    if (position != null) {
      _moveCameraToPosition(LatLng(position.latitude, position.longitude));
      _startLocationTracking();
    }
  }

  void _startLocationTracking() {
    if (_positionStreamSubscription != null) return;
    if (!_locationPermissionGranted) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
            _updateMarkers(); // Update current location marker
          });
        }
      },
      onError: (error) {
        _logger.e("Location tracking error: $error");
      },
    );
    _logger.i('Started location tracking stream.');
  }

  Future<void> _moveCameraToPosition(LatLng position, {double zoom = 16.0, bool animate = false}) async {
    try {
      _googleMapController ??= await _mapController.future;
      final cameraUpdate = CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: zoom),
      );
      if (animate && _googleMapController != null) {
        await _googleMapController!.animateCamera(cameraUpdate);
      } else if (_googleMapController != null) {
        await _googleMapController!.moveCamera(cameraUpdate);
      }
    } catch (e) {
      _logger.e("Error moving map camera: $e");
    }
  }

  // --- Routing Methods ---
  LatLng? _parseCoordinates(String input) {
     try {
      final parts = input.split(",");
      if (parts.length == 2) {
        return LatLng(
          double.parse(parts[0].trim()),
          double.parse(parts[1].trim()),
        );
      }
    } catch (_) {
      // Silently fail on parse errors
    }
    return null;
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return LatLng(locations.first.latitude, locations.first.longitude);
      }
    } catch (e) {
      _logger.e("Geocoding error for '$address': $e");
    }
    return null;
  }

  Future<String?> _reverseGeocode(LatLng position) async {
     try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks.first;
        return [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
      }
    } catch (e) {
      _logger.e("Reverse geocoding error: $e");
    }
    return null;
  }

  Future<void> _geocodeOrigin() async {
    if (_originController.text.isEmpty) return;
    setState(() {
      _isSearchingOrigin = true;
    });
    LatLng? coords = _parseCoordinates(_originController.text);
    coords ??= await _geocodeAddress(_originController.text);
    String? address = _originController.text;
    if (coords == null) {
      address = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find starting location.')),
        );
      }
    }
    setState(() {
      _isSearchingOrigin = false;
      _originPosition = coords;
      _originAddress = address;
      _updateMarkers();
    });
  }

  Future<void> _geocodeDestination() async {
    if (_destinationController.text.isEmpty) return;
    setState(() {
      _isSearchingDestination = true;
    });
    LatLng? coords = _parseCoordinates(_destinationController.text);
    coords ??= await _geocodeAddress(_destinationController.text);
    String? address = _destinationController.text;
    if (coords == null) {
      address = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find destination.')),
        );
      }
    }
    setState(() {
      _isSearchingDestination = false;
      _destinationPosition = coords;
      _destinationAddress = address;
      _updateMarkers();
    });
  }

  Future<void> _getRoute({bool checkSafety = false}) async {
    // Clear previous safety highlights
    setState(() {
      _showHotspotsOnRoute = checkSafety;
      // Reset polyline color if needed
      _polylines.removeWhere((p) => p.polylineId == const PolylineId("route"));
    });

    if (_destinationController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a destination.')),
        );
      }
      return;
    }
    if (_destinationPosition == null || _destinationController.text != _destinationAddress) {
      await _geocodeDestination();
      if (_destinationPosition == null) return;
    }

    LatLng? originCoords;
    if (_useCurrentLocationAsOrigin) {
      originCoords = _currentPosition;
      if (originCoords == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Current location not available.')),
          );
        }
        return;
      }
    } else {
      if (_originController.text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a starting location.')),
          );
        }
        return;
      }
      if (_originPosition == null || _originController.text != _originAddress) {
        await _geocodeOrigin();
        if (_originPosition == null) return;
      }
      originCoords = _originPosition;
    }

    if (_destinationPosition == null || originCoords == null) return;

    _updateMarkers(); // Ensure origin/destination markers are set

    try {
      PointLatLng origin = PointLatLng(originCoords.latitude, originCoords.longitude);
      PointLatLng destination = PointLatLng(_destinationPosition!.latitude, _destinationPosition!.longitude);

      final request = PolylineRequest(
        origin: origin,
        destination: destination,
        mode: TravelMode.driving,
      );

      PolylineResult result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: googleApiKey,
        request: request,
      );

      if (result.points.isNotEmpty) {
        _polylineCoordinates.clear();
        for (final point in result.points) {
          _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }

        bool routeIsSafe = true;
        if (checkSafety) {
          // Check if route passes through any hotspots
          routeIsSafe = !_isRouteIntersectingHotspots(_polylineCoordinates, _hotspots);
          _logger.i("Route safety check: ${routeIsSafe ? 'Clear' : 'Intersects Hotspots'}");
        }

        setState(() {
          // Add or update the route polyline
          _polylines.add(
            Polyline(
              polylineId: const PolylineId("route"),
              color: checkSafety && !routeIsSafe ? Colors.orange : Colors.blue, // Highlight if unsafe
              points: _polylineCoordinates,
              width: 5,
            ),
          );
          // Show hotspot circles if checking safety, regardless of intersection
          _showHotspotsOnRoute = checkSafety;
          _updateHotspotCircles(); // Ensure circles are updated based on state
        });
        _adjustCameraToFitRoute();

        if (checkSafety && !routeIsSafe && mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Warning: Route passes through hotspot areas.'), backgroundColor: Colors.orange),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Directions not found: ${result.errorMessage ?? 'Unknown error'}")),
          );
        }
      }
    } catch (e) {
      _logger.e("Error getting directions: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error getting directions: $e")));
      }
    }
  }

  // Route intersection check with hotspots
  bool _isRouteIntersectingHotspots(List<LatLng> routePoints, List<LatLng> hotspots) {
    if (hotspots.isEmpty || routePoints.isEmpty) return false;
    
    // More robust geometric intersection check
    const double thresholdDistance = 100; // Meters (should match circle radius)
    
    for (var point in routePoints) {
      for (var hotspot in hotspots) {
        double distance = Geolocator.distanceBetween(
          point.latitude, point.longitude,
          hotspot.latitude, hotspot.longitude,
        );
        if (distance <= thresholdDistance) {
          return true; // Found intersection
        }
      }
    }
    return false;
  }

  void _updateMarkers() async {
    final Set<Marker> updatedMarkers = {};

    if (_currentPosition != null) {
      String? address = await _reverseGeocode(_currentPosition!); // Fetch address
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("currentLocation"),
          position: _currentPosition!,
          infoWindow: InfoWindow(
            title: "My Current Location",
            snippet: address ?? "Fetching address...",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    if (!_useCurrentLocationAsOrigin && _originPosition != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("originLocation"),
          position: _originPosition!,
          infoWindow: InfoWindow(
            title: "Starting Point",
            snippet: _originAddress ?? "Custom location",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    }

    if (_destinationPosition != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("destinationLocation"),
          position: _destinationPosition!,
          infoWindow: InfoWindow(
            title: "Destination",
            snippet: _destinationAddress ?? "Selected destination",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    if (mounted) {
      setState(() {
        _markers.clear();
        _markers.addAll(updatedMarkers);
      });
    }
  }

  void _adjustCameraToFitRoute() async {
    if (_polylineCoordinates.isEmpty) return;

    double minLat = _polylineCoordinates.first.latitude;
    double maxLat = _polylineCoordinates.first.latitude;
    double minLng = _polylineCoordinates.first.longitude;
    double maxLng = _polylineCoordinates.first.longitude;

    for (final point in _polylineCoordinates) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      _googleMapController ??= await _mapController.future;
      if (_googleMapController != null) {
         _googleMapController!.animateCamera(
           CameraUpdate.newLatLngBounds(bounds, 50.0), // 50.0 padding
         );
      }
    } catch (e) {
      _logger.e("Error adjusting camera to fit route: $e");
    }
  }

  void _changeMapType(MapType type) {
    setState(() {
      _currentMapType = type;
    });
     _logger.i("Map type changed to: $type");
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (GoogleMapController controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
              _googleMapController = controller;
              // Optionally move camera to current location once map is ready
              if (_currentPosition != null) {
                _moveCameraToPosition(_currentPosition!);
              }
            },
            myLocationEnabled: _locationPermissionGranted,
            myLocationButtonEnabled: false, // Using custom buttons
            markers: _markers,
            polylines: _polylines,
            circles: _showHotspotsOnRoute ? _hotspotCircles : const {}, // Show hotspots conditionally
            padding: const EdgeInsets.only(bottom: 180, top: 60), // Adjust padding for controls
          ),
          // Routing Controls Overlay
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Origin Input
                    Row(
                      children: [
                        Checkbox(
                          value: _useCurrentLocationAsOrigin,
                          onChanged: (bool? value) {
                            setState(() {
                              _useCurrentLocationAsOrigin = value ?? true;
                              if (_useCurrentLocationAsOrigin) {
                                _originController.clear();
                                _originPosition = null;
                                _originAddress = null;
                                _updateMarkers();
                              }
                            });
                          },
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _originController,
                            enabled: !_useCurrentLocationAsOrigin,
                            decoration: InputDecoration(
                              labelText: _useCurrentLocationAsOrigin ? 'Using Current Location' : 'Enter Starting Location',
                              hintText: 'Address or Lat,Lng',
                              suffixIcon: _isSearchingOrigin
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : (_useCurrentLocationAsOrigin || _originController.text.isEmpty)
                                      ? null
                                      : IconButton(icon: const Icon(Icons.search), onPressed: _geocodeOrigin),
                            ),
                            onFieldSubmitted: (_) => _geocodeOrigin(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Destination Input
                    TextFormField(
                      controller: _destinationController,
                      decoration: InputDecoration(
                        labelText: 'Enter Destination Location',
                        hintText: 'Address or Lat,Lng',
                        suffixIcon: _isSearchingDestination
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : (_destinationController.text.isEmpty)
                                ? null
                                : IconButton(icon: const Icon(Icons.search), onPressed: _geocodeDestination),
                      ),
                      onFieldSubmitted: (_) => _geocodeDestination(),
                    ),
                    const SizedBox(height: 8),
                    // Action Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.directions),
                          label: const Text('Route'),
                          onPressed: () => _getRoute(checkSafety: false),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.shield_outlined),
                          label: const Text('Safe Route'),
                          onPressed: () => _getRoute(checkSafety: true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreen),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Map Type Toggle Buttons
          Positioned(
            bottom: 10,
            left: 10,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Column(
                  children: [
                     IconButton(
                       icon: Icon(Icons.map, color: _currentMapType == MapType.normal ? Theme.of(context).primaryColor : Colors.grey),
                       tooltip: 'Normal View',
                       onPressed: () => _changeMapType(MapType.normal),
                     ),
                     IconButton(
                       icon: Icon(Icons.satellite, color: _currentMapType == MapType.satellite ? Theme.of(context).primaryColor : Colors.grey),
                       tooltip: 'Satellite View',
                       onPressed: () => _changeMapType(MapType.satellite),
                     ),
                     IconButton(
                       icon: Icon(Icons.terrain, color: _currentMapType == MapType.terrain ? Theme.of(context).primaryColor : Colors.grey),
                       tooltip: 'Terrain View',
                       onPressed: () => _changeMapType(MapType.terrain),
                     ),
                  ],
                ),
              ),
            ),
          ),
          // Center on My Location Button
          Positioned(
            bottom: 10,
            right: 10,
            child: FloatingActionButton(
              mini: true,
              tooltip: 'Center on My Location',
              onPressed: _locationPermissionGranted && _currentPosition != null
                  ? () => _moveCameraToPosition(_currentPosition!, animate: true)
                  : null,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
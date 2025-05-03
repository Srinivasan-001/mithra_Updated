import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:logger/logger.dart';
import 'dart:math';
import 'package:geocoding/geocoding.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore (removed, unused)

import '../../data/repositories/hotspot_repository.dart'; // Import Hotspot Repository
import '../../domain/entities/hotspot.dart'; // Import Hotspot Entity

// TODO: Move API key to a secure config location
const String googleApiKey =
    "AIzaSyCq2s28kdJlvauO88jHCwqjW2vwrEAmsA8"; // Replace with your actual API key securely

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Logger _logger = Logger();
  final Completer<GoogleMapController> _mapController = Completer();
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
  bool _showSaferRoute = false; // State for the safer route switch
  bool _routeIsUnsafe =
      false; // State to track if the current route intersects hotspots

  // Geocoding
  bool _isSearchingOrigin = false;
  bool _isSearchingDestination = false;
  String? _originAddress;
  String? _destinationAddress;

  // Map Type
  MapType _currentMapType = MapType.normal;

  // Hotspots
  late HotspotRepository _hotspotRepository;
  StreamSubscription? _hotspotSubscription;
  final Set<Circle> _hotspotCircles = {};
  List<Hotspot> _currentHotspots =
      []; // Store current hotspots for route checking

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962), // Default: Googleplex
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _initializeHotspots(); // Initialize hotspot fetching

    _originController.addListener(() {
      if (_originPosition != null && _originController.text != _originAddress) {
        setState(() => _originPosition = null);
      }
    });
    _destinationController.addListener(() {
      if (_destinationPosition != null &&
          _destinationController.text != _destinationAddress) {
        setState(() => _destinationPosition = null);
      }
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _hotspotSubscription?.cancel(); // Cancel hotspot stream
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _initializeHotspots() {
    // IMPORTANT: User needs to add Firebase config files for this to work.
    try {
      _hotspotRepository = HotspotRepository();
      _hotspotSubscription = _hotspotRepository.getHotspotsStream().listen(
        (hotspots) {
          _logger.i("Received ${hotspots.length} hotspots from Firestore.");
          _updateHotspotCircles(hotspots);
          if (mounted) {
            setState(() {
              _currentHotspots = hotspots; // Update current hotspots list
              // Re-check route safety if polylines exist
              if (_polylineCoordinates.isNotEmpty) {
                _checkAndUpdateRouteSafety();
              }
            });
          }
        },
        onError: (error) {
          _logger.e("Error in hotspot stream: $error");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Error loading hotspots: $error. Ensure Firebase is configured.",
                ),
              ),
            );
          }
        },
      );
    } catch (e) {
      _logger.e(
        "Failed to initialize HotspotRepository: $e. Likely Firebase not initialized. User needs to add config files.",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Hotspot feature requires Firebase setup. Please add configuration files.",
            ),
          ),
        );
      }
    }
  }

  void _updateHotspotCircles(List<Hotspot> hotspots) {
    final Set<Circle> circles = {};
    for (final hotspot in hotspots) {
      circles.add(
        Circle(
          circleId: CircleId(hotspot.id),
          center: hotspot.position,
          radius: hotspot.radius,
          fillColor: Colors.red.withAlpha(
            (0.3 * 255).toInt(),
          ), // .withOpacity deprecated, use .withAlpha
          strokeColor: Colors.red,
          strokeWidth: 1,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _hotspotCircles.clear();
        _hotspotCircles.addAll(circles);
      });
    }
  }

  // --- Location & Map Methods ---
  Future<void> _requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied || status.isRestricted) {
      _logger.i("Requesting location permission...");
      status = await Permission.locationWhenInUse.request();
    }
    if (mounted) {
      setState(() {
        _locationPermissionGranted = status.isGranted;
      });
    }
    if (status.isGranted) {
      _logger.i("Location permission granted.");
      _getCurrentLocationAndTrack();
    } else {
      _logger.w("Location permission denied. Status: $status");
      if (status.isPermanentlyDenied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Location permission permanently denied. Please enable it in app settings.",
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<Position?> _getLatestLocation() async {
    if (!_locationPermissionGranted) {
      _logger.w("Cannot get location: Permission not granted.");
      await _requestLocationPermission();
      if (!_locationPermissionGranted) return null;
    }
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position!.latitude, position.longitude);
        });
      }
      _logger.i(
        "Fetched latest location: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}",
      );
      return position;
    } catch (e) {
      _logger.e("Error getting latest location: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not get current location: $e")),
        );
      }
      return null;
    }
  }

  Future<void> _getCurrentLocationAndTrack() async {
    Position? position = await _getLatestLocation();
    if (position != null) {
      _moveCameraToCurrentPosition();
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
            _updateMarkers();
          });
        }
      },
      onError: (error) {
        _logger.e("Location tracking error: $error");
      },
    );
    _logger.i("Started location tracking stream.");
  }

  Future<void> _moveCameraToCurrentPosition({bool animate = false}) async {
    if (_currentPosition != null) {
      try {
        final GoogleMapController controller = await _mapController.future;
        final cameraUpdate = CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentPosition!, zoom: 16.0),
        );
        if (animate) {
          controller.animateCamera(cameraUpdate);
        } else {
          controller.moveCamera(cameraUpdate);
        }
      } catch (e) {
        _logger.e("Error moving map camera: $e");
      }
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
    } catch (_) {}
    return null;
  }

  Future<LatLng?> _geocodeAddress(String address) async {
    try {
      List<Location> locations = await locationFromAddress(address);
      if (locations.isNotEmpty) {
        return LatLng(locations.first.latitude, locations.first.longitude);
      }
    } catch (e) {
      _logger.e("Geocoding error for 	'$address	': $e");
    }
    return null;
  }

  Future<void> _geocodeOrigin() async {
    if (_originController.text.isEmpty) return;
    setState(() => _isSearchingOrigin = true);
    LatLng? coords =
        _parseCoordinates(_originController.text) ??
        await _geocodeAddress(_originController.text);
    String? address = _originController.text;
    if (coords == null) {
      address = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find starting location.	')),
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
    setState(() => _isSearchingDestination = true);
    LatLng? coords =
        _parseCoordinates(_destinationController.text) ??
        await _geocodeAddress(_destinationController.text);
    String? address = _destinationController.text;
    if (coords == null) {
      address = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find destination.	')),
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

  Future<void> _getRoute() async {
    // Destination check
    if (_destinationController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a destination.	')),
        );
      }
      return;
    }
    if (_destinationPosition == null ||
        _destinationController.text != _destinationAddress) {
      await _geocodeDestination();
      if (_destinationPosition == null) return;
    }

    // Origin check
    LatLng? originCoords;
    if (_useCurrentLocationAsOrigin) {
      originCoords = _currentPosition;
      if (originCoords == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Current location not available.	')),
          );
        }
        return;
      }
    } else {
      if (_originController.text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a starting location.	')),
          );
        }
        return;
      }
      if (_originPosition == null || _originController.text != _originAddress) {
        await _geocodeOrigin();
        if (_originPosition == null) {
          return;
        }
      }
      originCoords = _originPosition;
    }

    if (_destinationPosition == null || originCoords == null) return;

    _updateMarkers(); // Ensure markers are up-to-date before drawing route

    try {
      PointLatLng origin = PointLatLng(
        originCoords.latitude,
        originCoords.longitude,
      );
      PointLatLng destination = PointLatLng(
        _destinationPosition!.latitude,
        _destinationPosition!.longitude,
      );

      // --- Standard Route Calculation ---
      PolylineResult result = await _polylinePoints.getRouteBetweenCoordinates(
        googleApiKey: googleApiKey,
        request: PolylineRequest(
          origin: origin,
          destination: destination,
          mode: TravelMode.driving,
        ),
      );

      if (result.points.isNotEmpty) {
        _polylineCoordinates.clear();
        for (final point in result.points) {
          _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
        }

        // --- Check Route Safety & Update Polyline ---
        _checkAndUpdateRouteSafety();

        // --- Alternate Route Logic (Placeholder) ---
        if (_showSaferRoute && _routeIsUnsafe) {
          _logger.w(
            "Route intersects hotspots and 'Safer Route' is ON. Calculating alternate route is needed.",
          );
          // TODO: Implement alternate route calculation here.
          // This might involve calling the API again with avoidance parameters
          // or requesting multiple routes and selecting the safest one.
          // For now, we just log and show the unsafe route with a warning color.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Warning: Route passes through hotspot area. Alternate route calculation not yet implemented.",
                ),
              ),
            );
          }
        }

        _adjustCameraToFitRoute();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Directions not found: ${result.errorMessage ?? 'Unknown error'}",
              ),
            ),
          );
        }
        // Clear previous route if new one not found
        setState(() {
          _polylines.clear();
          _polylineCoordinates.clear();
          _routeIsUnsafe = false;
        });
      }
    } catch (e) {
      _logger.e("Error getting directions: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error getting directions: $e")));
      }
    }
  }

  // Helper function to check intersection and update polyline state
  void _checkAndUpdateRouteSafety() {
    bool intersects = _checkRouteIntersection(
      _polylineCoordinates,
      _currentHotspots,
    );
    Color routeColor = Colors.blueAccent; // Default color
    if (intersects) {
      _logger.i("Route intersects with one or more hotspots.");
      if (_showSaferRoute) {
        // TODO: When alternate route is implemented, this color might be different
        routeColor =
            Colors
                .orange; // Indicate trying for safer, but showing original for now
      } else {
        routeColor =
            Colors
                .deepOrange; // Warning color for unsafe route when switch is off
      }
    } else {
      _logger.i("Route is clear of hotspots.");
    }

    setState(() {
      _routeIsUnsafe = intersects;
      _polylines.clear();
      if (_polylineCoordinates.isNotEmpty) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId("route"),
            color: routeColor,
            points: _polylineCoordinates,
            width: 6,
          ),
        );
      }
    });
  }

  // Simple check: checks if any vertex of the polyline is within any hotspot radius
  bool _checkRouteIntersection(
    List<LatLng> routePoints,
    List<Hotspot> hotspots,
  ) {
    if (routePoints.isEmpty || hotspots.isEmpty) {
      return false;
    }
    for (final point in routePoints) {
      for (final hotspot in hotspots) {
        double distance = Geolocator.distanceBetween(
          point.latitude,
          point.longitude,
          hotspot.position.latitude,
          hotspot.position.longitude,
        );
        if (distance <= hotspot.radius) {
          _logger.d(
            "Intersection detected: Point (${point.latitude}, ${point.longitude}) is within hotspot '${hotspot.name}' (Radius: ${hotspot.radius}m, Distance: ${distance.toStringAsFixed(2)}m)",
          );
          return true; // Found an intersection
        }
      }
    }
    // TODO: Implement a more robust check (line segment vs circle intersection) for better accuracy
    return false; // No intersection found
  }

  void _updateMarkers() async {
    final Set<Marker> updatedMarkers = {};

    if (_currentPosition != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("currentLocation"),
          position: _currentPosition!,
          infoWindow: const InfoWindow(title: "My Current Location"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (!_useCurrentLocationAsOrigin && _originPosition != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("origin"),
          position: _originPosition!,
          infoWindow: InfoWindow(title: "Origin: ${_originAddress ?? ''}"),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    if (_destinationPosition != null) {
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("destination"),
          position: _destinationPosition!,
          infoWindow: InfoWindow(
            title: "Destination: ${_destinationAddress ?? ''}",
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

    LatLngBounds bounds;
    if (_polylineCoordinates.length == 1) {
      bounds = LatLngBounds(
        southwest: _polylineCoordinates.first,
        northeast: _polylineCoordinates.first,
      );
    } else {
      double minLat = _polylineCoordinates.first.latitude,
          maxLat = _polylineCoordinates.first.latitude;
      double minLng = _polylineCoordinates.first.longitude,
          maxLng = _polylineCoordinates.first.longitude;
      for (final point in _polylineCoordinates) {
        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }
      bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );
    }

    try {
      final GoogleMapController controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60.0));
    } catch (e) {
      _logger.e("Error adjusting camera to fit route: $e");
    }
  }

  void _changeMapType(MapType type) {
    setState(() {
      _currentMapType = type;
    });
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            mapType: _currentMapType,
            myLocationEnabled: _locationPermissionGranted,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
            circles: _hotspotCircles,
            onMapCreated: (GoogleMapController controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
              if (_currentPosition != null) {
                _moveCameraToCurrentPosition();
              }
            },
          ),
          // Routing UI
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                        const Text("Use Current Location as Origin"),
                      ],
                    ),
                    if (!_useCurrentLocationAsOrigin)
                      TextField(
                        controller: _originController,
                        decoration: InputDecoration(
                          hintText: "Enter origin or coordinates",
                          labelText: "Origin",
                          suffixIcon:
                              _isSearchingOrigin
                                  ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _geocodeOrigin,
                                  ),
                        ),
                        onSubmitted: (_) => _geocodeOrigin(),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _destinationController,
                      decoration: InputDecoration(
                        hintText: "Enter destination or coordinates",
                        labelText: "Destination",
                        suffixIcon:
                            _isSearchingDestination
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: _geocodeDestination,
                                ),
                      ),
                      onSubmitted: (_) => _geocodeDestination(),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _getRoute,
                      icon: const Icon(Icons.directions),
                      label: const Text("Get Directions"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          40,
                        ), // Make button wider
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Map Type Selector & My Location Button
          Positioned(
            bottom: 80, // Position adjusted to make space for the switch
            right: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'myLocationBtn',
                  mini: true,
                  tooltip: 'My Location',
                  onPressed: () => _moveCameraToCurrentPosition(animate: true),
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  heroTag: 'mapTypeBtn',
                  mini: true,
                  tooltip: 'Map Layers',
                  child: const Icon(Icons.layers),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) {
                        return Wrap(
                          children: <Widget>[
                            ListTile(
                              leading: const Icon(Icons.map),
                              title: const Text('Normal'),
                              onTap: () {
                                _changeMapType(MapType.normal);
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.satellite_alt),
                              title: const Text('Satellite'),
                              onTap: () {
                                _changeMapType(MapType.satellite);
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.terrain),
                              title: const Text('Terrain'),
                              onTap: () {
                                _changeMapType(MapType.terrain);
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.layers_outlined),
                              title: const Text('Hybrid'),
                              onTap: () {
                                _changeMapType(MapType.hybrid);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          // Safer Route Switch
          Positioned(
            bottom: 20, // Position at bottom left
            left: 10,
            child: Card(
              elevation: 4.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Safer Route"),
                    Switch(
                      value: _showSaferRoute,
                      onChanged: (value) {
                        setState(() {
                          _showSaferRoute = value;
                          // Re-check route safety and update polyline color if a route exists
                          if (_polylineCoordinates.isNotEmpty) {
                            _checkAndUpdateRouteSafety();
                            if (_showSaferRoute && _routeIsUnsafe) {
                              _logger.w(
                                "'Safer Route' toggled ON for an unsafe route. Alternate route calculation needed.",
                              );
                              // TODO: Trigger alternate route calculation if needed
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Warning: Safer route option enabled, but alternate route calculation is not yet implemented.",
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

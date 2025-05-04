import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:logger/logger.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

// TODO: Securely manage API Key - consider using environment variables or Flutter flavors
const String googleApiKey = "AIzaSyCq2s28kdJlvauO88jHCwqjW2vwrEAmsA8"; // Replace with your actual key management strategy

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
  List<Map<String, dynamic>> _hotspots = []; // Updated to store full hotspot data
  bool _isLoadingHotspots = false;
  bool _displayAllHotspots = false; // New state variable to control general hotspot visibility

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
    _fetchHotspots(); // Fetch hotspot data from Firestore

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

  // --- Hotspot Methods with Firestore Integration ---
  Future<void> _fetchHotspots() async {
    if (_isLoadingHotspots) return;

    try {
      setState(() {
        _isLoadingHotspots = true;
      });

      // Connect to Firestore and fetch hotspot data
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('hotspots') // Ensure this collection name matches your Firestore
          .get();

      if (mounted) {
        setState(() {
          // Convert Firestore documents to usable map data
          _hotspots = snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>?; // Cast data
            final GeoPoint? location = data?["location"] as GeoPoint?; // Get the GeoPoint field
            return {
              "id": doc.id,
              // Extract lat/lng from GeoPoint, provide defaults if null or field missing
              "lat": location?.latitude ?? 0.0,
              "lng": location?.longitude ?? 0.0,
              "radius": (data?["radius"] as num?)?.toDouble() ?? 100.0, // Handle int/double from Firestore
              "risk_level": data?["risk_level"] as String? ?? "medium", // Default risk level
              "description": data?["description"] as String? ?? "", // Optional description
            };
          }).toList();

          _isLoadingHotspots = false;
          _updateHotspotCircles(); // Update circles once data is fetched
        });
      }

      _logger.i("Fetched ${_hotspots.length} hotspots from Firebase.");
    } catch (e) {
      _logger.e("Error fetching hotspots from Firebase: $e");
      if (mounted) {
        setState(() {
          _isLoadingHotspots = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not load safety data: $e")),
        );
      }
    }
  }

  // Helper function to get color based on risk level
  Color _getHotspotColor(String? riskLevel) {
    switch (riskLevel?.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.yellow;
      default:
        return Colors.grey; // Use a default color for unknown/missing risk
    }
  }

  void _updateHotspotCircles() {
    _hotspotCircles.clear();

    for (final hotspot in _hotspots) {
      final riskLevel = hotspot['risk_level'] as String? ?? 'medium';
      final circleColor = _getHotspotColor(riskLevel);

      _hotspotCircles.add(
        Circle(
          circleId: CircleId('hotspot_${hotspot['id']}'),
          center: LatLng(hotspot['lat'], hotspot['lng']),
          radius: hotspot['radius'] ?? 100.0, // Use the radius from data or default
          fillColor: circleColor.withAlpha(70),
          strokeColor: circleColor,
          strokeWidth: 2,
        ),
      );
    }
    // No need to call setState here as this is usually called within another setState
  }

  // Check if a single location falls within any hotspot
  Map<String, dynamic>? _checkLocationInHotspot(LatLng location) {
    if (_hotspots.isEmpty) return null;

    for (var hotspot in _hotspots) {
      double distance = Geolocator.distanceBetween(
        location.latitude, location.longitude,
        hotspot["lat"],
        hotspot["lng"],
      );

      double thresholdDistance = hotspot["radius"] ?? 100.0;

      if (distance <= thresholdDistance) {
        _logger.i("Location (${location.latitude}, ${location.longitude}) is inside hotspot ${hotspot["id"]}");
        return hotspot; // Return the hotspot data if found
      }
    }
    return null; // Location is not in any hotspot
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
      distanceFilter: 10, // Update location every 10 meters
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
      final parts = input.replaceAll(' ', '').split(","); // Remove spaces before splitting
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
        // Construct a readable address string
        return [
          place.name,
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
    String? address = _originController.text; // Assume input is address unless coords were parsed
    if (coords == null) {
      address = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find starting location.')),
        );
      }
    } else {
       // If coords were parsed, try to get an address for the marker
       address = await _reverseGeocode(coords) ?? _originController.text;
    }

    // Check if the geocoded origin is in a hotspot before updating state
    if (coords != null) {
      final hotspotInfo = _checkLocationInHotspot(coords);
      if (hotspotInfo != null && mounted) {
        final riskLevel = hotspotInfo["risk_level"] ?? "unknown";
        final color = _getHotspotColor(riskLevel);
        // Use WidgetsBinding to show SnackBar after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) { // Check mounted again inside callback
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text("Warning: Starting location is in a $riskLevel-risk hotspot area."),
                 backgroundColor: color.withAlpha((255 * 0.8).round()), // Replaced deprecated withOpacity
               ),
             );
          }
        });
      }
    }
    setState(() {
      _isSearchingOrigin = false;
      _originPosition = coords;
      _originAddress = address; // Store potentially reverse-geocoded address
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
    } else {
       address = await _reverseGeocode(coords) ?? _destinationController.text;
    }

    // Check if the geocoded destination is in a hotspot before updating state
    if (coords != null) {
      final hotspotInfo = _checkLocationInHotspot(coords);
      if (hotspotInfo != null && mounted) {
        final riskLevel = hotspotInfo["risk_level"] ?? "unknown";
        final color = _getHotspotColor(riskLevel);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(
                 content: Text("Warning: Destination is in a $riskLevel-risk hotspot area."),
                 backgroundColor: color.withAlpha((255 * 0.8).round()), // Replaced deprecated withOpacity
               ),
             );
          }
        });
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
    // Clear previous route polyline and potentially turn on hotspots for safe route
    setState(() {
      _polylines.removeWhere((p) => p.polylineId == const PolylineId("route"));
      _polylines.removeWhere((p) => p.polylineId == const PolylineId("alternate_route")); // Also clear alternate
      _polylineCoordinates.clear();
      // *** Automatically enable hotspot visibility when calculating a safe route ***
      if (checkSafety) {
        _displayAllHotspots = true;
        // Ensure circles are generated if not already
        if (_hotspotCircles.isEmpty && _hotspots.isNotEmpty) {
           _updateHotspotCircles();
        }
      }
    });

    if (_destinationController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a destination.')),
        );
      }
      return;
    }
    // Ensure destination is geocoded if text changed or position is null
    if (_destinationPosition == null || _destinationController.text != _destinationAddress) {
      await _geocodeDestination();
      if (_destinationPosition == null) return; // Geocoding failed
    }

    LatLng? originCoords;
    if (_useCurrentLocationAsOrigin) {
      originCoords = _currentPosition;
      if (originCoords == null) {
        Position? currentPos = await _getLatestLocation(); // Try fetching if null
        if (currentPos == null) {
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Current location not available.')),
             );
           }
           return;
        }
        originCoords = LatLng(currentPos.latitude, currentPos.longitude);
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
      // Ensure origin is geocoded if text changed or position is null
      if (_originPosition == null || _originController.text != _originAddress) {
        await _geocodeOrigin();
        if (_originPosition == null) return; // Geocoding failed
      }
      originCoords = _originPosition;
    }

    if (_destinationPosition == null || originCoords == null) return;

    _updateMarkers(); // Ensure origin/destination markers are set correctly

    try {
      PointLatLng origin = PointLatLng(originCoords.latitude, originCoords.longitude);
      PointLatLng destination = PointLatLng(_destinationPosition!.latitude, _destinationPosition!.longitude);

      final _ = PolylineRequest(
        origin: origin,
        destination: destination,
        mode: TravelMode.driving,
        alternatives: checkSafety, // Request alternatives only when checking safety
      );

      // Corrected logic to handle route fetching based on checkSafety
      List<PolylineResult> results;
      if (checkSafety) {
        // Request alternatives only when checking safety
        final safeRequest = PolylineRequest(
          origin: origin,
          destination: destination,
          mode: TravelMode.driving,
          alternatives: true, // Explicitly request alternatives
        );
        // Use getRouteWithAlternatives which returns List<PolylineResult>
        results = await _polylinePoints.getRouteWithAlternatives(
            googleApiKey: googleApiKey,
            request: safeRequest,
        );
      } else {
        // Request only the default route
        final defaultRequest = PolylineRequest(
          origin: origin,
          destination: destination,
          mode: TravelMode.driving,
          alternatives: false, // Explicitly request no alternatives
        );
        // Use getRouteBetweenCoordinates which returns PolylineResult
        PolylineResult singleResult = await _polylinePoints.getRouteBetweenCoordinates(
            googleApiKey: googleApiKey,
            request: defaultRequest,
        );
        // Wrap the single result in a list for consistent processing later
        // Check if the result has points before adding to the list
        if (singleResult.points.isNotEmpty) {
           results = [singleResult];
        } else {
           // Handle error case where even the single route failed
           results = []; // Assign empty list if single result is invalid
           _logger.e("Default route calculation failed: ${singleResult.errorMessage}");
        }
      }

      PolylineResult? selectedResult;
      bool selectedRouteIsSafe = true; // Assume safe initially

      if (results.isNotEmpty) {
        if (checkSafety) {
          // Find the first safe route among alternatives (if any)
          selectedResult = results.first; // Start with the default route
          selectedRouteIsSafe = !_isRouteIntersectingHotspots(
              selectedResult.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
              _hotspots
          );

          if (!selectedRouteIsSafe && results.length > 1) {
             _logger.i("Default route intersects hotspots. Checking alternatives...");
             for (int i = 1; i < results.length; i++) {
                final alternativeResult = results[i];
                if (alternativeResult.points.isNotEmpty) {
                   List<LatLng> currentRouteCoords = alternativeResult.points
                       .map((point) => LatLng(point.latitude, point.longitude))
                       .toList();
                   if (!_isRouteIntersectingHotspots(currentRouteCoords, _hotspots)) {
                     selectedResult = alternativeResult;
                     selectedRouteIsSafe = true;
                     _logger.i("Found a safe alternative route (index $i).");
                     break; // Use the first safe alternative found
                   }
                }
             }
             if (!selectedRouteIsSafe) {
                _logger.w("No safe alternative route found. Using the default (unsafe) route.");
             }
          }
        } else {
          // If not checking safety, just use the first (default) result
          selectedResult = results.first;
          selectedRouteIsSafe = true; // Not checked, assume safe for display purposes
        }

        if (selectedResult != null && selectedResult.points.isNotEmpty) {
          _polylineCoordinates.clear();
          for (final point in selectedResult.points) {
            _polylineCoordinates.add(LatLng(point.latitude, point.longitude));
          }

          setState(() {
            // Add or update the route polyline
            _polylines.add(
              Polyline(
                polylineId: const PolylineId("route"),
                color: checkSafety && !selectedRouteIsSafe ? Colors.orange : Colors.blueAccent, // Highlight if unsafe
                points: _polylineCoordinates,
                width: 5,
              ),
            );
            _updateHotspotCircles(); // Ensure circles are updated based on fetched data
          });
          _adjustCameraToFitRoute();

          if (checkSafety && !selectedRouteIsSafe && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Warning: Route passes through hotspot areas. Consider an alternative."), backgroundColor: Colors.orange),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Directions not found: ${selectedResult?.errorMessage ?? results.first.errorMessage ?? 'Unknown error'}")),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Directions not found. No routes returned.")),
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
  bool _isRouteIntersectingHotspots(List<LatLng> routePoints, List<Map<String, dynamic>> hotspots) {
    if (hotspots.isEmpty || routePoints.isEmpty) return false;

    for (var point in routePoints) {
      for (var hotspot in hotspots) {
        double distance = Geolocator.distanceBetween(
          point.latitude, point.longitude,
          hotspot['lat'], hotspot['lng'],
        );

        double thresholdDistance = hotspot['radius'] ?? 100.0;

        if (distance <= thresholdDistance) {
          _logger.i("Route intersects hotspot ${hotspot['id']} near (${point.latitude}, ${point.longitude})");
          return true; // Found intersection
        }
      }
    }
    return false;
  }

  void _updateMarkers() async {
    final Set<Marker> updatedMarkers = {};

    if (_currentPosition != null) {
      String? address = await _reverseGeocode(_currentPosition!); // Fetch address for info window
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("currentLocation"),
          position: _currentPosition!,
          infoWindow: InfoWindow(
            title: "My Current Location",
            snippet: address ?? "Lat: ${_currentPosition!.latitude.toStringAsFixed(4)}, Lng: ${_currentPosition!.longitude.toStringAsFixed(4)}",
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
            snippet: _originAddress ?? "Lat: ${_originPosition!.latitude.toStringAsFixed(4)}, Lng: ${_originPosition!.longitude.toStringAsFixed(4)}",
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
            snippet: _destinationAddress ?? "Lat: ${_destinationPosition!.latitude.toStringAsFixed(4)}, Lng: ${_destinationPosition!.longitude.toStringAsFixed(4)}",
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

    // Also consider origin and destination markers if they exist
    if (_originPosition != null) {
       minLat = min(minLat, _originPosition!.latitude);
       maxLat = max(maxLat, _originPosition!.latitude);
       minLng = min(minLng, _originPosition!.longitude);
       maxLng = max(maxLng, _originPosition!.longitude);
    }
     if (_destinationPosition != null) {
       minLat = min(minLat, _destinationPosition!.latitude);
       maxLat = max(maxLat, _destinationPosition!.latitude);
       minLng = min(minLng, _destinationPosition!.longitude);
       maxLng = max(maxLng, _destinationPosition!.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      _googleMapController ??= await _mapController.future;
      if (_googleMapController != null) {
         _googleMapController!.animateCamera(
           CameraUpdate.newLatLngBounds(bounds, 60.0), // Increased padding
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
      // Added AppBar for better structure
      appBar: AppBar(
        title: const Text("Safe Route Finder"),
        actions: [
          // Refresh hotspots button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Hotspots',
            onPressed: _isLoadingHotspots ? null : _fetchHotspots,
          ),
        ],
      ),
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
              // Move camera to current location once map is ready and permission granted
              if (_locationPermissionGranted && _currentPosition != null) {
                _moveCameraToPosition(_currentPosition!);
              }
            },
            myLocationEnabled: _locationPermissionGranted,
            myLocationButtonEnabled: false, // Using custom FAB
            markers: _markers,
            polylines: _polylines,
            // Corrected logic: Show circles only if the toggle is enabled
            circles: _displayAllHotspots ? _hotspotCircles : const {},
            padding: const EdgeInsets.only(bottom: 60, top: 180), // Adjusted padding for controls and FABs
          ),
          // Routing Controls Overlay
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Origin Input Row
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
                                _updateMarkers(); // Remove origin marker if switching to current location
                              } else {
                                // Optionally try to geocode if text exists when unchecked
                                if (_originController.text.isNotEmpty) {
                                  _geocodeOrigin();
                                }
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
                              // Clear button for origin
                              suffixIcon: !_useCurrentLocationAsOrigin && _originController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _originController.clear();
                                      setState(() {
                                        _originPosition = null;
                                        _originAddress = null;
                                        _updateMarkers();
                                      });
                                    },
                                  )
                                : null,
                            ),
                            onFieldSubmitted: (_) {
                              if (!_useCurrentLocationAsOrigin) _geocodeOrigin();
                            },
                          ),
                        ),
                        // Search button for origin (only if manual input)
                        if (!_useCurrentLocationAsOrigin)
                          _isSearchingOrigin
                            ? const Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(icon: const Icon(Icons.search), onPressed: _geocodeOrigin),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Destination Input Row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _destinationController,
                            decoration: InputDecoration(
                              labelText: 'Enter Destination Location',
                              hintText: 'Address or Lat,Lng',
                              // Clear button for destination
                              suffixIcon: _destinationController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _destinationController.clear();
                                      setState(() {
                                        _destinationPosition = null;
                                        _destinationAddress = null;
                                        _updateMarkers();
                                        // Clear route as well
                                        _polylines.clear();
                                        _polylineCoordinates.clear();
                                      });
                                    },
                                  )
                                : null,
                            ),
                            onFieldSubmitted: (_) => _geocodeDestination(),
                          ),
                        ),
                        // Search button for destination
                        _isSearchingDestination
                          ? const Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                          : IconButton(icon: const Icon(Icons.search), onPressed: _geocodeDestination),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Action Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.directions),
                          label: const Text('Route'),
                          onPressed: (_destinationPosition != null || _destinationController.text.isNotEmpty) && (_useCurrentLocationAsOrigin || _originPosition != null || _originController.text.isNotEmpty)
                              ? () => _getRoute(checkSafety: false)
                              : null, // Disable if no destination/origin
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.shield_outlined),
                          label: const Text('Safe Route'),
                          onPressed: (_destinationPosition != null || _destinationController.text.isNotEmpty) && (_useCurrentLocationAsOrigin || _originPosition != null || _originController.text.isNotEmpty)
                              ? () => _getRoute(checkSafety: true)
                              : null, // Disable if no destination/origin
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.lightGreen),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Floating Action Buttons Area
          Positioned(
            bottom: 10,
            right: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Center on My Location Button
                FloatingActionButton(
                  mini: true,
                  heroTag: 'fab_location', // Unique heroTag
                  tooltip: 'Center on My Location',
                  onPressed: _locationPermissionGranted && _currentPosition != null
                      ? () => _moveCameraToPosition(_currentPosition!, animate: true)
                      : null,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                // Hotspot toggle button
                FloatingActionButton(
                  mini: true,
                  heroTag: 'fab_hotspots', // Unique heroTag
                  tooltip: 'Toggle Hotspots Display',
                  backgroundColor: _displayAllHotspots ? Theme.of(context).colorScheme.secondary : Colors.grey[300],
                  onPressed: () {
                    setState(() {
                      _displayAllHotspots = !_displayAllHotspots;
                      // If turning on and circles haven't been generated yet, generate them.
                      if (_displayAllHotspots && _hotspotCircles.isEmpty && _hotspots.isNotEmpty) {
                        _updateHotspotCircles();
                      }
                    });
                  },
                  // Corrected icon logic based on _displayAllHotspots
                  child: Icon(_displayAllHotspots ? Icons.visibility : Icons.visibility_off),
                ),
              ],
            ),
          ),
          // Map Type Toggle Buttons (Moved to bottom left)
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
          // Show loading indicator when fetching hotspots
          if (_isLoadingHotspots)
            Container(
              color: Colors.black.withAlpha((255 * 0.3).round()), // Replaced deprecated withOpacity
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

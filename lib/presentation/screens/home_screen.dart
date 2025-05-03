import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:logger/logger.dart'; // Added for logging
import 'package:twilio_flutter/twilio_flutter.dart'; // Added for SMS
import 'dart:math'; // Added for min/max
import 'package:geocoding/geocoding.dart'; // Added for geocoding addresses

import '../../presentation/blocs/auth_bloc.dart';
import '../../presentation/widgets/emergency_button.dart';
import '../../core/config/twilio_config.dart';
import '../../core/services/fall_detection_service.dart'; // Import Fall Detection Service
import 'profile_screen.dart'; // Import Profile Screen
import 'dashboard_screen.dart'; // Import Dashboard Screen

const String googleApiKey =
    "AIzaSyCq2s28kdJlvauO88jHCwqjW2vwrEAmsA8"; // Replace with your actual API key securely

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Logger _logger = Logger(); // Logger for debugging
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
  bool _useCurrentLocationAsOrigin =
      true; // Toggle for using current location or custom origin

  // Geocoding
  bool _isSearchingOrigin = false;
  bool _isSearchingDestination = false;
  String? _originAddress;
  String? _destinationAddress;

  // Fall Detection
  late FallDetectionService _fallDetectionService;
  final bool _isFallDetectionActive =
      true; // Control activation via UI later if needed
  bool _isSendingFallAlert = false; // State for automatic alert sending

  // Twilio
  late TwilioFlutter twilioFlutter;

  // User Data for Drawer Header
  String? _userName;
  String? _userEmail;
  StreamSubscription? _userStreamSubscription;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(
      37.42796133580664,
      -122.085749655962,
    ), // Default location (e.g., Googleplex)
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _fetchUserData(); // Fetch user data for drawer

    // Initialize Twilio
    twilioFlutter = TwilioFlutter(
      accountSid: twilioAccountSid,
      authToken: twilioAuthToken,
      twilioNumber: twilioPhoneNumber,
    );

    // Initialize and start Fall Detection Service
    _fallDetectionService = FallDetectionService(
      onFallDetected: _handleFallDetected, // Pass the callback method
    );
    if (_isFallDetectionActive) {
      _fallDetectionService.startListening();
    }

    // Add listeners to text controllers to clear cached positions when text changes
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
    _userStreamSubscription?.cancel(); // Cancel user data stream
    _originController.dispose();
    _destinationController.dispose();
    _fallDetectionService.dispose(); // Dispose fall detection service
    super.dispose();
  }

  // --- User Data Fetching ---
  void _fetchUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userStreamSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (snapshot) {
              if (mounted && snapshot.exists) {
                final data = snapshot.data();
                setState(() {
                  _userName = data?['name'] as String?;
                  _userEmail = data?['email'] as String?;
                  // Note: Emergency contacts are fetched separately in _handleFallDetected
                });
              }
            },
            onError: (error) {
              _logger.e("Error fetching user data: $error");
            },
          );
    }
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
              : 'Location permission is required to send alerts with your location.';
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
      // Attempt to request permission again, or inform the user
      await _requestLocationPermission();
      if (!_locationPermissionGranted) return null;
    }
    try {
      // Use getLastKnownPosition for a quick check, then getCurrentPosition if needed
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Consider a time limit if immediate response is critical
          // timeLimit: Duration(seconds: 10),
        ),
      );
      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position!.latitude, position.longitude);
        });
      }
      _logger.i(
        'Fetched latest location: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}',
      );
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
      _moveCameraToCurrentPosition(); // Move camera once initially
      _startLocationTracking(); // Start continuous tracking
    }
  }

  void _startLocationTracking() {
    if (_positionStreamSubscription != null) return; // Already tracking
    if (!_locationPermissionGranted) return; // Don't track without permission

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update only when moved 10 meters
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
        // Optionally inform user, but avoid spamming snackbars
      },
    );
    _logger.i('Started location tracking stream.');
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

  // --- Routing Methods (Keep existing implementations) ---
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

  Future<void> _getRoute() async {
    if (_destinationController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a destination.')),
        );
      }
      return;
    }
    if (_destinationPosition == null ||
        _destinationController.text != _destinationAddress) {
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
        if (_originPosition == null) {
          return;
        }
      }
      originCoords = _originPosition;
    }

    if (_destinationPosition == null || originCoords == null) return;

    _updateMarkers();

    try {
      PointLatLng origin = PointLatLng(
        originCoords.latitude,
        originCoords.longitude,
      );
      PointLatLng destination = PointLatLng(
        _destinationPosition!.latitude,
        _destinationPosition!.longitude,
      );

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
        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId("route"),
              color: Colors.blue,
              points: _polylineCoordinates,
              width: 5,
            ),
          );
        });
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

  void _updateMarkers() async {
    final Set<Marker> updatedMarkers = {};

    if (_currentPosition != null) {
      String? address = await _reverseGeocode(
        _currentPosition!,
      ); // Fetch address
      updatedMarkers.add(
        Marker(
          markerId: const MarkerId("currentLocation"),
          position: _currentPosition!,
          infoWindow: InfoWindow(
            title: "My Current Location",
            snippet: address ?? "Fetching address...",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
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
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
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
      final GoogleMapController controller = await _mapController.future;
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50.0),
      ); // 50.0 padding
    } catch (e) {
      _logger.e("Error adjusting camera to fit route: $e");
    }
  }

  // --- Fall Detection & Alert Methods ---

  void _handleFallDetected() {
    // Prevent triggering multiple alerts simultaneously
    if (_isSendingFallAlert) {
      _logger.i("Fall detected, but an alert is already being sent.");
      return;
    }

    _logger.i("Fall detected! Initiating alert process...");
    if (mounted) {
      setState(() {
        _isSendingFallAlert = true;
      });
      // Show immediate feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fall detected! Sending emergency alert...'),
          duration: Duration(seconds: 5),
        ),
      );
    }

    // Call the function to send the alert
    _sendEmergencyAlert();
  }

  Future<void> _sendEmergencyAlert() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e("Cannot send alert: User not logged in.");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error: Not logged in.')));
        setState(() {
          _isSendingFallAlert = false;
        });
      }
      return;
    }

    // 1. Get Current Location
    final Position? position = await _getLatestLocation();
    if (position == null) {
      _logger.e("Cannot send alert: Failed to get location.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Could not get location for alert.'),
          ),
        );
        setState(() {
          _isSendingFallAlert = false;
        });
      }
      return;
    }
    final locationLink =
        "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
    String? address = await _reverseGeocode(
      LatLng(position.latitude, position.longitude),
    );
    final locationInfo =
        address != null
            ? "near $address"
            : "at coordinates ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}";

    // 2. Get Emergency Contacts from Firestore
    List<Map<String, String>> emergencyContacts = [];
    try {
      final docSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      if (docSnapshot.exists &&
          docSnapshot.data()!.containsKey('emergencyContacts')) {
        final contactsData =
            docSnapshot.data()!['emergencyContacts'] as List<dynamic>?;
        if (contactsData != null) {
          emergencyContacts =
              contactsData
                  .map((contact) {
                    return {
                      'name': contact['name'] as String? ?? 'N/A',
                      'phone': contact['phone'] as String? ?? '',
                    };
                  })
                  .where((contact) => contact['phone']!.isNotEmpty)
                  .toList();
        }
      }
    } catch (e) {
      _logger.e("Error fetching emergency contacts: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error fetching emergency contacts.')),
        );
        // Continue without contacts? Or stop?
        // For now, we stop.
        setState(() {
          _isSendingFallAlert = false;
        });
        return;
      }
    }

    if (emergencyContacts.isEmpty) {
      _logger.w(
        "Cannot send alert: No emergency contacts found or configured.",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No emergency contacts configured. Please add them in your profile.',
            ),
          ),
        );
        setState(() {
          _isSendingFallAlert = false;
        });
      }
      return;
    }

    // 3. Construct and Send SMS via Twilio
    final userName = _userName ?? 'Someone'; // Use fetched name or default
    final messageBody =
        "Emergency Alert from Shield Guardian: $userName may have fallen and needs help! Location: $locationInfo. Map: $locationLink";

    int successCount = 0;
    int failureCount = 0;

    for (final contact in emergencyContacts) {
      final recipientPhone = contact['phone']!;
      // Basic validation (needs improvement for international numbers)
      if (recipientPhone.length < 10) {
        _logger.w("Skipping invalid phone number: $recipientPhone");
        failureCount++;
        continue;
      }

      try {
        _logger.i("Sending SMS to ${contact['name']} ($recipientPhone)...");
        await twilioFlutter.sendSMS(
          toNumber: recipientPhone,
          messageBody: messageBody,
        );
        _logger.i("SMS sent successfully to $recipientPhone.");
        successCount++;
      } catch (e) {
        _logger.e("Failed to send SMS to $recipientPhone: $e");
        failureCount++;
      }
    }

    // 4. Update UI and State
    if (mounted) {
      String finalMessage;
      if (successCount > 0 && failureCount == 0) {
        finalMessage =
            'Emergency alert sent successfully to $successCount contact(s).';
      } else if (successCount > 0 && failureCount > 0) {
        finalMessage =
            'Emergency alert sent to $successCount contact(s). Failed for $failureCount.';
      } else {
        // successCount == 0
        finalMessage = 'Failed to send emergency alert to any contacts.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(finalMessage),
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() {
        _isSendingFallAlert = false;
      });
    }
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Shield Guardian Home'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          // Example action: Center map on current location
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Center on My Location',
            onPressed:
                _locationPermissionGranted
                    ? _moveCameraToCurrentPosition
                    : null,
          ),
        ],
      ),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _initialCameraPosition,
            onMapCreated: (GoogleMapController controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
            myLocationEnabled: _locationPermissionGranted,
            myLocationButtonEnabled: false, // We use a custom button in AppBar
            markers: _markers,
            polylines: _polylines,
            padding: const EdgeInsets.only(bottom: 150), // Padding for controls
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
                              labelText:
                                  _useCurrentLocationAsOrigin
                                      ? 'Using Current Location'
                                      : 'Enter Starting Location',
                              hintText: 'Address or Lat,Lng',
                              suffixIcon:
                                  _isSearchingOrigin
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : (_useCurrentLocationAsOrigin ||
                                          _originController.text.isEmpty)
                                      ? null
                                      : IconButton(
                                        icon: const Icon(Icons.search),
                                        onPressed: _geocodeOrigin,
                                      ),
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
                        suffixIcon:
                            _isSearchingDestination
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : (_destinationController.text.isEmpty)
                                ? null
                                : IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: _geocodeDestination,
                                ),
                      ),
                      onFieldSubmitted: (_) => _geocodeDestination(),
                    ),
                    const SizedBox(height: 8),
                    // Get Route Button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions),
                      label: const Text('Get Directions'),
                      onPressed: _getRoute,
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
          // Emergency Button Overlay
          Positioned(
            bottom: 20,
            right: 20,
            child: EmergencyButton(
              onManualTrigger: () {
                _logger.i("Manual Emergency Button Pressed!");
                // Potentially show confirmation dialog before sending?
                if (!_isSendingFallAlert) {
                  // Prevent overlap with automatic fall alert
                  _sendEmergencyAlert(); // Trigger the same alert logic
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Alert already in progress...'),
                    ),
                  );
                }
              },
            ),
          ),
          // Loading indicator for sending alert
          if (_isSendingFallAlert)
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      "Sending Alert...",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Drawer Builder ---
  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_userName ?? 'Loading...'),
            accountEmail: Text(_userEmail ?? 'Loading...'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                _userName?.isNotEmpty == true
                    ? _userName![0].toUpperCase()
                    : '?',
                style: const TextStyle(fontSize: 40.0),
              ),
            ),
            decoration: const BoxDecoration(color: Colors.blue),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home / Map'),
            onTap: () {
              Navigator.pop(context); // Close the drawer
            },
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context); // Close drawer first
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DashboardScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context); // Close drawer first
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () {
              Navigator.pop(context); // Close the drawer
              context.read<AuthBloc>().add(SignOutRequested());
              // AuthBloc listener in main.dart will handle navigation
            },
          ),
        ],
      ),
    );
  }
}

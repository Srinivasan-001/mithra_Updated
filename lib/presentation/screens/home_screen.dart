import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:twilio_flutter/twilio_flutter.dart';
import 'package:geolocator/geolocator.dart'; // Keep for location in alerts
import 'package:geocoding/geocoding.dart'; // Keep for location in alerts
import 'package:permission_handler/permission_handler.dart'; // Keep for location permission

import '../../presentation/blocs/auth_bloc.dart';
import '../../presentation/widgets/emergency_button.dart';
import '../../core/config/twilio_config.dart';
import '../../core/services/fall_detection_service.dart';
import 'profile_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart'; // Import the new MapScreen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Logger _logger = Logger();

  // Keep location-related variables needed for alerts
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _locationPermissionGranted = false;

  // Fall Detection
  late FallDetectionService _fallDetectionService;
  final bool _isFallDetectionActive = true;
  bool _isSendingFallAlert = false;

  // Twilio
  late TwilioFlutter twilioFlutter;

  // User Data
  String? _userName;
  String? _userEmail;
  StreamSubscription? _userStreamSubscription;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission(); // Still need permission for alerts
    _fetchUserData();

    twilioFlutter = TwilioFlutter(
      accountSid: twilioAccountSid,
      authToken: twilioAuthToken,
      twilioNumber: twilioPhoneNumber,
    );

    _fallDetectionService = FallDetectionService(
      onFallDetected: _handleFallDetected,
    );
    if (_isFallDetectionActive) {
      _fallDetectionService.startListening();
    }

    // Start location tracking for alert purposes
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _userStreamSubscription?.cancel();
    _fallDetectionService.dispose();
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
                });
              }
            },
            onError: (error) {
              _logger.e("Error fetching user data: $error");
            },
          );
    }
  }

  // --- Location Methods (Simplified for Alert Context) ---
  Future<void> _requestLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isDenied || status.isRestricted) {
      _logger.i('Requesting location permission for alerts...');
      status = await Permission.locationWhenInUse.request();
    }
    if (mounted) {
       setState(() {
         _locationPermissionGranted = status.isGranted;
       });
    }
    if (!status.isGranted) {
       _logger.w('Location permission denied for alerts. Status: $status');
       // Optionally show a persistent warning if location is crucial for alerts
    }
  }

  Future<Position?> _getLatestLocation() async {
    if (!_locationPermissionGranted) {
      _logger.w('Cannot get location for alert: Permission not granted.');
      await _requestLocationPermission(); // Try again
      if (!_locationPermissionGranted) return null;
    }
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        // Update _currentPosition silently for alert usage
        _currentPosition = LatLng(position.latitude, position.longitude);
      }
      return position;
    } catch (e) {
      _logger.e("Error getting latest location for alert: $e");
      return null;
    }
  }

   void _startLocationTracking() {
    if (_positionStreamSubscription != null) return; // Already tracking
    if (!_locationPermissionGranted) {
        _requestLocationPermission(); // Try to get permission if not granted
        return; // Don't track without permission
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // Update less frequently if only for alerts
    );
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        if (mounted) {
           // Update _currentPosition silently
           _currentPosition = LatLng(position.latitude, position.longitude);
           _logger.d("Updated background location for alerts: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}");
        }
      },
      onError: (error) {
        _logger.e("Background location tracking error: $error");
      },
    );
    _logger.i('Started background location tracking for alerts.');
  }

  Future<String?> _reverseGeocode(LatLng position) async {
    // Keep this utility function for alert messages
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
      _logger.e("Reverse geocoding error for alert: $e");
    }
    return null;
  }

  // --- Fall Detection & Alert Methods (Keep as is) ---
  void _handleFallDetected() {
    if (_isSendingFallAlert) {
      _logger.i("Fall detected, but an alert is already being sent.");
      return;
    }
    _logger.i("Fall detected! Initiating alert process...");
    if (mounted) {
      setState(() {
        _isSendingFallAlert = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fall detected! Sending emergency alert...'),
          duration: Duration(seconds: 5),
        ),
      );
    }
    _sendEmergencyAlert();
  }

  Future<void> _sendEmergencyAlert() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _logger.e("Cannot send alert: User not logged in.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Not logged in.')));
        setState(() { _isSendingFallAlert = false; });
      }
      return;
    }

    final Position? position = await _getLatestLocation(); // Use the simplified location getter
    if (position == null) {
      _logger.e("Cannot send alert: Failed to get location.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Could not get location for alert.')));
        setState(() { _isSendingFallAlert = false; });
      }
      return;
    }
    final locationLink = "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}";
    String? address = await _reverseGeocode(LatLng(position.latitude, position.longitude));
    final locationInfo = address != null ? "near $address" : "at coordinates ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}";

    List<Map<String, String>> emergencyContacts = [];
    try {
      final docSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (docSnapshot.exists && docSnapshot.data()!.containsKey('emergencyContacts')) {
        final contactsData = docSnapshot.data()!['emergencyContacts'] as List<dynamic>?;
        if (contactsData != null) {
          emergencyContacts = contactsData.map((contact) {
            return {
              'name': contact['name'] as String? ?? 'N/A',
              'phone': contact['phone'] as String? ?? '',
            };
          }).where((contact) => contact['phone']!.isNotEmpty).toList();
        }
      }
    } catch (e) {
      _logger.e("Error fetching emergency contacts: $e");
      // Handle error appropriately
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error fetching emergency contacts.')));
         setState(() { _isSendingFallAlert = false; });
      }
      return;
    }

    if (emergencyContacts.isEmpty) {
      _logger.w("Cannot send alert: No emergency contacts configured.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No emergency contacts configured. Please add them in your profile.')));
        setState(() { _isSendingFallAlert = false; });
      }
      return;
    }

    final userName = _userName ?? 'Someone';
    // Use 'Mithra' as the app name in the alert message
    final messageBody = "Emergency Alert from Mithra: $userName may have fallen and needs help! Location: $locationInfo. Map: $locationLink";

    int successCount = 0;
    int failureCount = 0;
    for (final contact in emergencyContacts) {
      final recipientPhone = contact['phone']!;
      if (recipientPhone.length < 10) { // Basic validation
        _logger.w("Skipping invalid phone number: $recipientPhone");
        failureCount++;
        continue;
      }
      try {
        _logger.i("Sending SMS to ${contact['name']} ($recipientPhone)...");
        await twilioFlutter.sendSMS(toNumber: recipientPhone, messageBody: messageBody);
        _logger.i("SMS sent successfully to $recipientPhone.");
        successCount++;
      } catch (e) {
        _logger.e("Failed to send SMS to $recipientPhone: $e");
        failureCount++;
      }
    }

    if (mounted) {
      String finalMessage;
      if (successCount > 0 && failureCount == 0) {
        finalMessage = 'Emergency alert sent successfully to $successCount contact(s).';
      } else if (successCount > 0 && failureCount > 0) {
        finalMessage = 'Emergency alert sent to $successCount contact(s). Failed for $failureCount.';
      } else {
        finalMessage = 'Failed to send emergency alert to any contacts.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(finalMessage), duration: const Duration(seconds: 5)));
      setState(() { _isSendingFallAlert = false; });
    }
  }

  // --- UI Build Method (Simplified) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        // Change title to 'Mithra'
        title: const Text('Mithra'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        // Remove map-specific actions like my_location
      ),
      drawer: _buildDrawer(), // Keep the drawer
      body: Stack(
        children: [
          // Replace Map with a simple placeholder or welcome message
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.home_filled, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 20),
                Text(
                  'Welcome to Mithra!',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                 const SizedBox(height: 10),
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 32.0),
                   child: Text(
                     'Use the drawer menu to navigate to the Map, Dashboard, or Profile.',
                     textAlign: TextAlign.center,
                     style: Theme.of(context).textTheme.bodyMedium,
                   ),
                 ),
              ],
            ),
          ),
          // Keep Emergency Button Overlay (adjust position if needed)
          Positioned(
            bottom: 30, // Adjusted position
            right: 30,
            child: EmergencyButton(
              onManualTrigger: () {
                _logger.i("Manual Emergency Button Pressed!");
                if (!_isSendingFallAlert) {
                  _sendEmergencyAlert();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alert already in progress...')),
                  );
                }
              },
            ),
          ),
          // Keep Loading indicator for sending alert
          if (_isSendingFallAlert)
            Container(
              color: const Color.fromRGBO(0, 0, 0, 0.5),
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

  // --- Drawer Builder (Updated) ---
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
                _userName?.isNotEmpty == true ? _userName![0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 40.0),
              ),
            ),
            // Use app name 'Mithra' if needed here, or keep default style
            decoration: const BoxDecoration(color: Colors.blue), // Or use app theme color
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Home'), // Changed from 'Home / Map'
            onTap: () {
              Navigator.pop(context); // Close the drawer
              // Already on Home, do nothing or refresh?
            },
          ),
          // Add Map navigation item
          ListTile(
            leading: const Icon(Icons.map_outlined), // Use a map icon
            title: const Text('Map'),
            onTap: () {
              Navigator.pop(context); // Close drawer first
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MapScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DashboardScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Profile'),
            onTap: () {
              Navigator.pop(context);
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
              Navigator.pop(context);
              context.read<AuthBloc>().add(SignOutRequested());
            },
          ),
        ],
      ),
    );
  }
}

// Helper class LatLng needed for _currentPosition (can be moved to a common place)
class LatLng {
  final double latitude;
  final double longitude;
  const LatLng(this.latitude, this.longitude);
}


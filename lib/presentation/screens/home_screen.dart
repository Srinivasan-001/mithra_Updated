import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
// Removed: import 'package:flutter_sms/flutter_sms.dart';
import 'package:telephony/telephony.dart'; // Import telephony
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../presentation/blocs/auth_bloc.dart';
import '../../presentation/widgets/emergency_button.dart';
import '../../core/services/fall_detection_service.dart';
import 'profile_screen.dart';
import 'dashboard_screen.dart';
import 'map_screen.dart';

// Define LatLng if not available elsewhere
class LatLng {
  final double latitude;
  final double longitude;
  LatLng(this.latitude, this.longitude);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final Logger _logger = Logger();
  final Telephony telephony = Telephony.instance; // Instantiate Telephony

  // Location
  LatLng? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _locationPermissionGranted = false;
  bool _smsPermissionGranted = false; // Track SMS permission

  // Fall Detection
  late FallDetectionService _fallDetectionService;
  final bool _isFallDetectionActive = true;
  bool _isSendingFallAlert = false;

  // User Data
  String? _userName;
  String? _userEmail;
  StreamSubscription? _userStreamSubscription;

  // YouTube Player Controller
  late YoutubePlayerController _youtubeController;
  final String _videoId = YoutubePlayer.convertUrlToId("https://www.youtube.com/live/_iOLy51aA8Q?si=s9xDqHNzWSnPd0Hs") ?? 'dQw4w9WgXcQ';

  @override
  void initState() {
    super.initState();
    _requestPermissions(); // Request both location and SMS permissions
    _fetchUserData();

    _fallDetectionService = FallDetectionService(
      onFallDetected: _handleFallDetected,
    );
    if (_isFallDetectionActive) {
      _fallDetectionService.startListening();
    }

    // Location tracking starts after permission granted in _requestPermissions

    _youtubeController = YoutubePlayerController(
      initialVideoId: _videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        forceHD: false,
        loop: false,
        enableCaption: true,
      ),
    );

    _logger.i("HomeScreen initialized.");
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _userStreamSubscription?.cancel();
    _fallDetectionService.dispose();
    _youtubeController.dispose();
    super.dispose();
  }

  // --- Permissions ---
  Future<void> _requestPermissions() async {
    // Request Location Permission
    var locationStatus = await Permission.locationWhenInUse.status;
    if (locationStatus.isDenied || locationStatus.isRestricted) {
      _logger.i('Requesting location permission...');
      locationStatus = await Permission.locationWhenInUse.request();
    }
    final locationGranted = locationStatus.isGranted;
    if (mounted) {
      setState(() {
        _locationPermissionGranted = locationGranted;
      });
    }
    if (!locationGranted) {
      _logger.w('Location permission denied. Status: $locationStatus');
    } else {
      _logger.i('Location permission granted.');
      _startLocationTracking(); // Start tracking if permission granted
    }

    // Request SMS Permission
    var smsStatus = await Permission.sms.status;
    if (smsStatus.isDenied || smsStatus.isRestricted) {
      _logger.i('Requesting SMS permission...');
      smsStatus = await Permission.sms.request();
    }
    final smsGranted = smsStatus.isGranted;
     if (mounted) {
      setState(() {
        _smsPermissionGranted = smsGranted;
      });
    }
    if (!smsGranted) {
      _logger.w('SMS permission denied. Status: $smsStatus');
      // Show a persistent warning if SMS is crucial
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SMS permission denied. Emergency alerts cannot be sent directly.'), duration: Duration(seconds: 5)),
        );
      }
    } else {
       _logger.i('SMS permission granted.');
    }
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

  // --- Location Methods ---
  Future<Position?> _getLatestLocation() async {
    if (!_locationPermissionGranted) {
      _logger.w('Cannot get location: Permission not granted.');
      // Optionally re-request or guide user
      return null;
    }
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        _currentPosition = LatLng(position.latitude, position.longitude);
      }
      return position;
    } catch (e) {
      _logger.e("Error getting latest location: $e");
      return null;
    }
  }

   void _startLocationTracking() {
    if (_positionStreamSubscription != null) return;
    if (!_locationPermissionGranted) {
        _logger.i('Location tracking deferred until permission is granted.');
        return;
    }

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        if (mounted) {
           _currentPosition = LatLng(position.latitude, position.longitude);
           _logger.d("Updated location: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}");
        }
      },
      onError: (error) {
        _logger.e("Location tracking error: $error");
      },
    );
    _logger.i('Started location tracking.');
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

  // --- Fall Detection & Alert Methods ---
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

    // Check SMS permission before proceeding
    if (!_smsPermissionGranted) {
       _logger.w("Cannot send alert: SMS permission not granted.");
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: SMS permission required to send alerts.')));
         setState(() { _isSendingFallAlert = false; });
         // Optionally prompt for permission again
         _requestPermissions();
       }
       return;
    }

    final Position? position = await _getLatestLocation();
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
    final messageBody = "Emergency Alert from Mithra: $userName may need help! Location: $locationInfo. Map: $locationLink";
    final recipientPhones = emergencyContacts.map((c) => c['phone']!).toList();

    int successCount = 0;
    int failureCount = 0;

    // Use Telephony to send SMS
    for (final phone in recipientPhones) {
      try {
        _logger.i("Attempting to send SMS via Telephony to: $phone");
        await telephony.sendSms(
          to: phone,
          message: messageBody,
          isMultipart: true, // Send as multipart if message is long
        );
        // Listen for status updates (optional but recommended)
        // telephony.getSentMessageStatus.listen((SendStatus status) {
        //    _logger.i("SMS to $phone status: $status");
        //    // Handle status updates if needed
        // });
        _logger.i("Telephony sendSms initiated for $phone.");
        successCount++;
      } catch (error) {
        _logger.e("Failed to send SMS using Telephony to $phone: $error");
        failureCount++;
      }
    }

    // Update UI based on initiation counts (direct sending status might be async)
    if (mounted) {
      String finalMessage;
      if (successCount > 0 && failureCount == 0) {
        finalMessage = 'Emergency alert sending initiated for $successCount contact(s).';
      } else if (successCount > 0 && failureCount > 0) {
        finalMessage = 'Emergency alert initiated for $successCount contact(s). Failed to initiate for $failureCount.';
      } else {
        finalMessage = 'Failed to initiate emergency alert sending to any contacts.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(finalMessage), duration: const Duration(seconds: 5)));
      setState(() { _isSendingFallAlert = false; });
    }
  }

  // --- UI Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Mithra'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      drawer: _buildDrawer(),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildYoutubePlayer(),
                  const SizedBox(height: 24),
                  _buildFeatureSection(),
                  const SizedBox(height: 24),
                  _buildHowItWorksSection(),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30,
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

  // --- UI Helper Widgets ---

  Widget _buildYoutubePlayer() {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      clipBehavior: Clip.antiAlias,
      child: YoutubePlayer(
        controller: _youtubeController,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Colors.amber,
        progressColors: const ProgressBarColors(
          playedColor: Colors.amber,
          handleColor: Colors.amberAccent,
        ),
        onReady: () {
          _logger.i('YouTube Player is ready.');
        },
      ),
    );
  }

  Widget _buildFeatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'App Features',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildFeatureItem(
          icon: Icons.warning_amber_rounded,
          title: 'Automatic Fall Detection',
          description: 'Utilizes phone sensors to detect potential falls and automatically triggers alerts.',
        ),
        _buildFeatureItem(
          icon: Icons.sos,
          title: 'Manual SOS Button',
          description: 'Instantly send alerts with your location to emergency contacts with a single tap.',
        ),
        _buildFeatureItem(
          icon: Icons.location_on_outlined,
          title: 'Real-time Location Sharing',
          description: 'Alerts include a map link to your current location for quick assistance.',
        ),
         _buildFeatureItem(
          icon: Icons.map_outlined,
          title: 'Safety Zone Mapping',
          description: 'View and manage designated safe zones or identify potential hotspots on the map.',
        ),
        _buildFeatureItem(
          icon: Icons.contacts_outlined,
          title: 'Emergency Contact Management',
          description: 'Easily add and manage trusted contacts who will receive alerts.',
        ),
         _buildFeatureItem(
          icon: Icons.dashboard_customize_outlined,
          title: 'Activity Dashboard',
          description: 'Review safety-related statistics and activity summaries.',
        ),
      ],
    );
  }

  Widget _buildFeatureItem({required IconData icon, required String title, required String description}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 30, color: Theme.of(context).primaryColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How Mithra Protects You',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildStepItem(
          icon: Icons.sensors,
          step: '1. Detection',
          description: 'The app continuously monitors for falls using your phone\'s sensors, or you can manually trigger an alert using the SOS button.',
        ),
        _buildStepItem(
          icon: Icons.location_searching,
          step: '2. Location Pinpointing',
          description: 'Upon detecting an emergency, Mithra instantly gets your precise current location.',
        ),
        _buildStepItem(
          icon: Icons.sms_outlined,
          step: '3. Alert Dispatch',
          description: 'An SMS alert, including your name and a map link to your location, is sent to all your pre-configured emergency contacts.',
        ),
         _buildStepItem(
          icon: Icons.health_and_safety_outlined,
          step: '4. Assistance',
          description: 'Your contacts receive the alert and can quickly locate you or coordinate help.',
        ),
      ],
    );
  }

  Widget _buildStepItem({required IconData icon, required String step, required String description}) {
     return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).primaryColorLight,
            child: Icon(icon, size: 20, color: Theme.of(context).primaryColorDark),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodyMedium),
              ],
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
                _userName?.isNotEmpty == true ? _userName![0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 40.0),
              ),
            ),
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Map'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MapScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
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
            leading: const Icon(Icons.person_outline),
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
              // Correct way to dispatch logout event
              context.read<AuthBloc>().add(AuthCheckRequested());
            },
          ),
        ],
      ),
    );
  }
}


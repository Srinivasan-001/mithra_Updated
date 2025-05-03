import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

import 'edit_profile_screen.dart'; // Import the EditProfileScreen

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();
  User? _currentUser;
  Stream<DocumentSnapshot>? _userStream;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    if (_currentUser != null) {
      // Use a stream to listen for real-time updates
      _userStream = _firestore.collection('users').doc(_currentUser!.uid).snapshots();
    } else {
      _logger.w("ProfileScreen: User not logged in.");
      // Optionally navigate back or show login prompt if needed
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please log in to view your profile.')),
          );
          Navigator.pop(context); // Go back if not logged in
        }
      });
    }
  }

  // Helper to build detail items
  Widget _buildDetailItem(String label, String? value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 3),
                Text(
                  value != null && value.isNotEmpty ? value : 'Not provided',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper to build emergency contact cards
  Widget _buildEmergencyContactItem(Map<String, dynamic>? contactData, int index) {
    final name = contactData?['name'] as String?;
    final phone = contactData?['phone'] as String?;

    // Only display card if there's some data
    if ((name == null || name.isEmpty) && (phone == null || phone.isEmpty)) {
      return const SizedBox.shrink(); // Don't show empty contacts
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency Contact ${index + 1}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColorDark),
            ),
            const Divider(height: 16),
            _buildDetailItem('Name', name, Icons.person_outline),
            _buildDetailItem('Phone', phone, Icons.phone_outlined),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          // Add Edit Button
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Profile',
            onPressed: _currentUser == null ? null : () {
              // Navigate to EditProfileScreen
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EditProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            _logger.e("Error loading profile stream: ${snapshot.error}");
            return Center(child: Text('Error loading profile: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists || _currentUser == null) {
            return const Center(child: Text('Could not load user data.'));
          }

          // Data is available
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final emergencyContactsData = data['emergencyContacts'] as List<dynamic>?;
          final userName = data['name'] as String?;
          final userEmail = data['email'] as String?;

          return RefreshIndicator(
            onRefresh: () async {
              // While using a stream, manual refresh might not be strictly needed,
              // but it provides user feedback.
              setState(() {
                // Re-assign stream if needed, though Firestore stream handles updates.
                if (_currentUser != null) {
                  _userStream = _firestore.collection('users').doc(_currentUser!.uid).snapshots();
                }
              });
            },
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // --- User Header ---
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Theme.of(context).primaryColorLight,
                        child: Text(
                          userName?.isNotEmpty == true ? userName![0].toUpperCase() : (userEmail?.isNotEmpty == true ? userEmail![0].toUpperCase() : 'U'),
                          style: TextStyle(fontSize: 40, color: Theme.of(context).primaryColorDark),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        userName ?? 'User Name',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userEmail ?? 'No email provided',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // --- Personal Details ---
                _buildDetailItem('Gender', data['gender'], Icons.wc),
                _buildDetailItem('Phone Number', data['phone'], Icons.phone),
                _buildDetailItem('Address', data['address'], Icons.home_outlined),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // --- Emergency Contacts ---
                Text(
                  'Emergency Contacts',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (emergencyContactsData != null && emergencyContactsData.isNotEmpty)
                  ...List.generate(
                    emergencyContactsData.length,
                    (index) => _buildEmergencyContactItem(emergencyContactsData[index] as Map<String, dynamic>?, index),
                  ).where((widget) => widget is! SizedBox) // Filter out empty SizedBoxes
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No emergency contacts provided. Tap Edit to add them.', style: TextStyle(color: Colors.grey)),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}


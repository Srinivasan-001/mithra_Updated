import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final Logger _logger = Logger();
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers for editable fields
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyContact1NameController = TextEditingController();
  final _emergencyContact1PhoneController = TextEditingController();
  final _emergencyContact2NameController = TextEditingController();
  final _emergencyContact2PhoneController = TextEditingController();

  String? _email; // Email is usually not editable
  String? _selectedGender;
  final List<String> _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emergencyContact1NameController.dispose();
    _emergencyContact1PhoneController.dispose();
    _emergencyContact2NameController.dispose();
    _emergencyContact2PhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    if (_currentUser == null) {
      _logger.w("Cannot load profile data: User not logged in.");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: Not logged in.')),
        );
        Navigator.pop(context); // Go back if user is null
      }
      return;
    }

    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      if (mounted && docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;

        // Pre-fill controllers and state variables
        _nameController.text = data['name'] ?? '';
        _email = data['email']; // Store email (read-only)
        _phoneController.text = data['phone'] ?? '';
        _addressController.text = data['address'] ?? '';
        _selectedGender = data['gender'];
        // Ensure gender value exists in the list
        if (_selectedGender != null && !_genders.contains(_selectedGender)) {
          _selectedGender = null; // Reset if invalid value from DB
        }

        // Pre-fill emergency contacts
        final emergencyContacts = data['emergencyContacts'] as List<dynamic>? ?? [];
        if (emergencyContacts.isNotEmpty) {
          final contact1 = emergencyContacts[0] as Map<String, dynamic>?;
          _emergencyContact1NameController.text = contact1?['name'] ?? '';
          _emergencyContact1PhoneController.text = contact1?['phone'] ?? '';
        }
        if (emergencyContacts.length > 1) {
          final contact2 = emergencyContacts[1] as Map<String, dynamic>?;
          _emergencyContact2NameController.text = contact2?['name'] ?? '';
          _emergencyContact2PhoneController.text = contact2?['phone'] ?? '';
        }

        setState(() => _isLoading = false);
      } else if (mounted) {
        _logger.w("User document does not exist for UID: ${_currentUser!.uid}");
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find user data.')),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error loading user data for editing', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load data: $e')),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the errors in the form.')),
      );
      return;
    }

    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: Not logged in.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Prepare updated data map
    final updatedData = {
      'name': _nameController.text.trim(),
      'gender': _selectedGender,
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'emergencyContacts': [
        {
          'name': _emergencyContact1NameController.text.trim(),
          'phone': _emergencyContact1PhoneController.text.trim(),
        },
        {
          'name': _emergencyContact2NameController.text.trim(),
          'phone': _emergencyContact2PhoneController.text.trim(),
        },
      ],
      // Optionally add 'updatedAt': FieldValue.serverTimestamp()
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .update(updatedData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.pop(context); // Go back to the profile screen
      }
    } catch (e, stackTrace) {
      _logger.e('Error updating profile', error: e, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          // Save button in AppBar
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)),
                )
              : IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: 'Save Changes',
                  onPressed: _saveProfile,
                ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text(
                    'Personal Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Name Field
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.name,
                    enabled: !_isSaving,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Name cannot be empty';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Email Field (Read-only)
                  TextFormField(
                    initialValue: _email ?? 'Loading...', // Display email
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.black12, // Indicate read-only
                    ),
                    readOnly: true,
                  ),
                  const SizedBox(height: 16),

                  // Gender Dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      prefixIcon: Icon(Icons.wc),
                      border: OutlineInputBorder(),
                    ),
                    items: _genders.map((String gender) {
                      return DropdownMenuItem<String>(
                        value: gender,
                        child: Text(gender),
                      );
                    }).toList(),
                    onChanged: _isSaving ? null : (String? newValue) {
                      setState(() {
                        _selectedGender = newValue;
                      });
                    },
                    // No validator needed unless gender is mandatory
                  ),
                  const SizedBox(height: 16),

                  // Phone Number Field
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    enabled: !_isSaving,
                    // Optional: Add validator for phone format
                  ),
                  const SizedBox(height: 16),

                  // Address Field
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.home),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.streetAddress,
                    maxLines: 3,
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  const Text(
                    'Emergency Contacts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Emergency Contact 1
                  TextFormField(
                    controller: _emergencyContact1NameController,
                    decoration: const InputDecoration(
                      labelText: 'Contact 1 Name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.name,
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emergencyContact1PhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Contact 1 Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    enabled: !_isSaving,
                    // Optional: Add validator for phone format
                  ),
                  const SizedBox(height: 24),

                  // Emergency Contact 2
                  TextFormField(
                    controller: _emergencyContact2NameController,
                    decoration: const InputDecoration(
                      labelText: 'Contact 2 Name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.name,
                    enabled: !_isSaving,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emergencyContact2PhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Contact 2 Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    enabled: !_isSaving,
                    // Optional: Add validator for phone format
                  ),
                  const SizedBox(height: 32),

                  // Save Button (Alternative placement)
                  // ElevatedButton.icon(
                  //   icon: const Icon(Icons.save),
                  //   label: const Text('Save Changes'),
                  //   onPressed: _isSaving ? null : _saveProfile,
                  //   style: ElevatedButton.styleFrom(
                  //     minimumSize: const Size.fromHeight(45),
                  //   ),
                  // ),
                  // if (_isSaving) const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator())),
                ],
              ),
            ),
    );
  }
}


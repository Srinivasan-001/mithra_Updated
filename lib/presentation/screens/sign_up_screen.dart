import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart'; // Import Bloc
import 'package:logger/logger.dart';
// for kDebugMode
import '../blocs/auth_bloc.dart'; // Import AuthBloc

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers remain the same
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyContact1NameController = TextEditingController();
  final _emergencyContact1PhoneController = TextEditingController();
  final _emergencyContact2NameController = TextEditingController();
  final _emergencyContact2PhoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedGender;
  final List<String> _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  final Logger _logger = Logger();
  // _isLoading is now managed by Bloc state, but can be kept for UI disabling
  // bool _isLoading = false; // We'll rely on Bloc state

  void _signUp() {
    _logger.i('Sign-up process started'); // Log a message when sign-up starts
    if (!_formKey.currentState!.validate()) {
      // Optional: Show a snackbar if validation fails, though fields show errors
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Please fix the errors in the form')),
      // );
      return;
    }

    // Dispatch the event to the AuthBloc
    context.read<AuthBloc>().add(
          SignUpRequested(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
            name: _nameController.text.trim(),
            gender: _selectedGender,
            phone: _phoneController.text.trim(),
            address: _addressController.text.trim(),
            ec1Name: _emergencyContact1NameController.text.trim(),
            ec1Phone: _emergencyContact1PhoneController.text.trim(),
            ec2Name: _emergencyContact2NameController.text.trim(),
            ec2Phone: _emergencyContact2PhoneController.text.trim(),
          ),
        );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emergencyContact1NameController.dispose();
    _emergencyContact1PhoneController.dispose();
    _emergencyContact2NameController.dispose();
    _emergencyContact2PhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign Up'),
      ),
      // Use BlocListener to react to state changes (navigation, errors)
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) {
            // Navigate to home screen on successful authentication
            Navigator.pushReplacementNamed(context, '/home');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sign up successful!'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (state is AuthError) {
            // Show error message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                duration: const Duration(seconds: 4),
                backgroundColor: Colors.redAccent, // Indicate error
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: BlocBuilder<AuthBloc, AuthState>(
                // Use BlocBuilder to reflect loading state in the UI
                builder: (context, state) {
                  final isLoading = state is AuthLoading;

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Create Your Account',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.name,
                        enabled: !isLoading,
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
                        onChanged: isLoading
                            ? null
                            : (String? newValue) {
                                setState(() {
                                  _selectedGender = newValue;
                                });
                              },
                      ),
                      const SizedBox(height: 16),

                      // Email Field (Required)
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email *',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !isLoading,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+")
                              .hasMatch(value)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
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
                        enabled: !isLoading,
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
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Emergency Contact 1
                      const Text('Emergency Contact 1',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emergencyContact1NameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.name,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emergencyContact1PhoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Emergency Contact 2
                      const Text('Emergency Contact 2',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emergencyContact2NameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.name,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _emergencyContact2PhoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          prefixIcon: Icon(Icons.phone_outlined),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Password Field (Required)
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'Password *',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        enabled: !isLoading,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Password is required';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters long';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Sign Up Button
                      isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                textStyle: const TextStyle(fontSize: 16),
                              ),
                              onPressed: _signUp, // Call the updated _signUp method
                              child: const Text('Sign Up'),
                            ),
                      const SizedBox(height: 16),

                      // Login Navigation
                      TextButton(
                        onPressed: isLoading
                            ? null
                            : () {
                                Navigator.pop(context); // Go back to login
                              },
                        child: const Text('Already have an account? Log In'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for InputFormatters
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../blocs/auth_bloc.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();

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
  bool _isPasswordVisible = false; // State for password visibility

  void _signUp() {
    _logger.i('Sign-up process started');
    if (!_formKey.currentState!.validate()) {
      return;
    }

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
      body: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is Authenticated) {
            Navigator.pushReplacementNamed(context, '/home');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sign up successful!'),
                duration: Duration(seconds: 2),
              ),
            );
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                duration: const Duration(seconds: 4),
                backgroundColor: Colors.redAccent,
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
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Name is required'; // Added validation
                          }
                          return null;
                        },
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
                        // Optional: Add validator if gender is required
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

                      // Phone Number Field (10 digits validation)
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number *',
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone, // Use phone keyboard
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly, // Allow only digits
                          LengthLimitingTextInputFormatter(10), // Limit to 10 digits
                        ],
                        enabled: !isLoading,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          if (value.length != 10) {
                            return 'Phone number must be exactly 10 digits';
                          }
                          return null;
                        },
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
                        // Optional: Add validator if address is required
                      ),
                      const SizedBox(height: 24),

                      // Emergency Contact 1
                      const Text('Emergency Contact 1', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
                        // Optional: Add validator if required
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
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly], // Allow only digits
                        enabled: !isLoading,
                        // Optional: Add validator (e.g., length)
                      ),
                      const SizedBox(height: 24),

                      // Emergency Contact 2
                      const Text('Emergency Contact 2', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 24),

                      // Password Field (Required with visibility toggle)
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password *',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                        obscureText: !_isPasswordVisible, // Toggle based on state
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
                              onPressed: _signUp,
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


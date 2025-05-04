import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode
import '../../core/constants/routes.dart';
import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final Logger _logger = Logger();
  bool _isLoading = false;
  bool _isPasswordVisible = false; // State for password visibility

  Future<void> signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email and password cannot be empty'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(email)) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid email address'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      if (e.code == 'user-not-found' || e.code == 'invalid-credential' || e.code == 'wrong-password') {
        errorMessage = 'Invalid email or password. Please try again.';
      } else if (e.code == 'invalid-email') {
         errorMessage = 'The email address format is invalid.';
      } else if (e.code == 'user-disabled') {
         errorMessage = 'This user account has been disabled.';
      } else {
        errorMessage = 'Login failed. Please try again later.';
        if (kDebugMode) {
           _logger.e('FirebaseAuthException during sign in', error: e, stackTrace: StackTrace.current);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
         _logger.e('Error during sign in', error: e, stackTrace: stackTrace);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An unexpected error occurred. Please try again.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
       if (mounted) {
         setState(() {
           _isLoading = false;
         });
       }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            color: Colors.white,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFE3F2FD),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: const Icon(
                          Icons.security,
                          size: 80,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Shield Guardian', // Assuming this is the app name, or change to 'Mithra'
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome back! Sign in to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 48),
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      // Updated Password Field with visibility toggle
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Password',
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
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 48),
                      _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton.icon(
                            onPressed: signIn,
                            icon: const Icon(Icons.login),
                            label: const Text('Sign in'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(fontSize: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _isLoading ? null : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignUpScreen(),
                            ),
                          );
                        },
                        child: const Text('Don\'t have an account? Sign Up'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


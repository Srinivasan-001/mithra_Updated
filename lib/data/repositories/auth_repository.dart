import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Firestore
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart'; // for kDebugMode

class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Add Firestore instance
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final Logger _logger = Logger();

  // Sign up with Email and Password
  Future<User?> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String name,
    String? gender,
    required String phone,
    required String address,
    required String ec1Name,
    required String ec1Phone,
    required String ec2Name,
    required String ec2Phone,
  }) async {
    try {
      // Create user in Firebase Auth
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      // Save additional user data to Firestore
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'gender': gender,
          'email': email,
          'phone': phone,
          'address': address,
          'emergencyContacts': [
            {'name': ec1Name, 'phone': ec1Phone},
            {'name': ec2Name, 'phone': ec2Phone},
          ],
          'createdAt': Timestamp.now(),
        });
        return user; // Return the user object on success
      } else {
        // This case should ideally not happen if createUserWithEmailAndPassword succeeds
        throw Exception('User creation succeeded but user object is null.');
      }
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        _logger.e('FirebaseAuthException during sign up in repository', error: e);
      }
      // Re-throw the specific FirebaseAuthException to be handled in the BLoC
      rethrow;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        _logger.e('Error during sign up or Firestore save in repository', error: e, stackTrace: stackTrace);
      }
      // Throw a generic exception for other errors
      throw Exception('An unexpected error occurred during sign up: ${e.toString()}');
    }
  }

  // Sign in with Google (existing method)
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _logger.i('Google sign in cancelled by user.');
        return null; // User cancelled the sign-in
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);

      // Optional: Check if user data exists in Firestore and add if not
      // This might be relevant if users can sign up with email/pass AND Google
      // await _checkAndCreateFirestoreUser(userCredential.user);

      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        _logger.e('FirebaseAuthException signing in with Google', error: e);
      }
      // Handle specific errors if needed, or just rethrow/return null
      rethrow; // Re-throw to be handled by BLoC
    } catch (e, stackTrace) {
      if (kDebugMode) {
        _logger.e('Error signing in with Google', error: e, stackTrace: stackTrace);
      }
      throw Exception('An unexpected error occurred during Google sign in: ${e.toString()}');
    }
  }

  // Sign out (existing method)
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      _logger.i('User signed out successfully.');
    } catch (e, stackTrace) {
       if (kDebugMode) {
        _logger.e('Error signing out', error: e, stackTrace: stackTrace);
      }
      // Re-throw the exception to be handled by the BLoC
      throw Exception('An error occurred during sign out: ${e.toString()}');
    }
  }

  // Auth state changes stream (existing)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Current user getter (existing)
  User? get currentUser => _auth.currentUser;

  // Helper to check/create Firestore user data (optional, example)
  /*
  Future<void> _checkAndCreateFirestoreUser(User? user) async {
    if (user == null) return;
    final docRef = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) {
      _logger.i('Creating Firestore document for new Google Sign-In user: ${user.uid}');
      await docRef.set({
        'uid': user.uid,
        'name': user.displayName ?? 'N/A',
        'email': user.email,
        'phone': user.phoneNumber ?? '', // Google sign-in might not provide phone
        'address': '', // Address usually not available from Google Sign-In
        'emergencyContacts': [], // Initialize empty emergency contacts
        'createdAt': Timestamp.now(),
        // Add other default fields as needed
      });
    }
  }
  */
}


import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/repositories/auth_repository.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {}

class SignInRequested extends AuthEvent {}

class SignUpRequested extends AuthEvent {
  final String email;
  final String password;
  final String name;
  final String? gender;
  final String phone;
  final String address;
  final String ec1Name;
  final String ec1Phone;
  final String ec2Name;
  final String ec2Phone;

  SignUpRequested({
    required this.email,
    required this.password,
    required this.name,
    this.gender,
    required this.phone,
    required this.address,
    required this.ec1Name,
    required this.ec1Phone,
    required this.ec2Name,
    required this.ec2Phone,
  });

  @override
  List<Object?> get props => [
        email,
        password,
        name,
        gender,
        phone,
        address,
        ec1Name,
        ec1Phone,
        ec2Name,
        ec2Phone,
      ];
}

class SignOutRequested extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class Authenticated extends AuthState {
  final User user;
  Authenticated(this.user);

  @override
  List<Object?> get props => [user];
}

class Unauthenticated extends AuthState {}

class AuthLoading extends AuthState {}

class AuthError extends AuthState {
  final String message;
  AuthError(this.message);

  @override
  List<Object?> get props => [message];
}

// Bloc
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;

  AuthBloc({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<SignInRequested>(_onSignInRequested);
    on<SignUpRequested>(_onSignUpRequested); // Register the new event handler
    on<SignOutRequested>(_onSignOutRequested);
  }

  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    // No need for loading state here, initial check should be quick
    try {
      final user = _authRepository.currentUser;
      if (user != null) {
        emit(Authenticated(user));
      } else {
        emit(Unauthenticated());
      }
    } catch (e) {
      // Handle potential errors during initial check if necessary
      emit(AuthError('Error checking authentication status: ${e.toString()}'));
      emit(Unauthenticated()); // Fallback to unauthenticated
    }
  }

  Future<void> _onSignInRequested(
    SignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      // Assuming signInWithGoogle is the only sign-in method for now
      final credential = await _authRepository.signInWithGoogle();
      if (credential?.user != null) {
        emit(Authenticated(credential!.user!));
      } else {
        // If credential is null but no exception, it might mean user cancelled
        emit(Unauthenticated());
      }
    } on FirebaseAuthException catch (e) {
      emit(AuthError('Sign in failed: ${e.message ?? e.code}'));
      emit(Unauthenticated()); // Ensure state returns to Unauthenticated on error
    } catch (e) {
      emit(AuthError('An unexpected error occurred during sign in: ${e.toString()}'));
      emit(Unauthenticated()); // Ensure state returns to Unauthenticated on error
    }
  }

  Future<void> _onSignUpRequested(
    SignUpRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      final user = await _authRepository.signUpWithEmailAndPassword(
        email: event.email,
        password: event.password,
        name: event.name,
        gender: event.gender,
        phone: event.phone,
        address: event.address,
        ec1Name: event.ec1Name,
        ec1Phone: event.ec1Phone,
        ec2Name: event.ec2Name,
        ec2Phone: event.ec2Phone,
      );
      if (user != null) {
        emit(Authenticated(user));
      } else {
        // This case should ideally be handled by exceptions in the repository
        emit(AuthError('Sign up failed: Unknown error.'));
        emit(Unauthenticated());
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      if (e.code == 'email-already-in-use') {
        errorMessage = 'This email is already registered.';
      } else if (e.code == 'weak-password') {
        errorMessage = 'The password is too weak.';
      } else if (e.code == 'invalid-email') {
         errorMessage = 'The email address is not valid.';
      } else {
        errorMessage = 'Sign-up failed: ${e.message ?? e.code}';
      }
      emit(AuthError(errorMessage));
      emit(Unauthenticated()); // Ensure state returns to Unauthenticated on error
    } catch (e) {
      emit(AuthError('An unexpected error occurred during sign up: ${e.toString()}'));
      emit(Unauthenticated()); // Ensure state returns to Unauthenticated on error
    }
  }

  Future<void> _onSignOutRequested(
    SignOutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    try {
      await _authRepository.signOut();
      emit(Unauthenticated());
    } on FirebaseAuthException catch (e) {
      emit(AuthError('Sign out failed: ${e.message ?? e.code}'));
      // Keep the user authenticated if sign out fails?
      // Or emit Authenticated(currentUser) if needed, but Unauthenticated seems safer
      final user = _authRepository.currentUser;
      if (user != null) {
        emit(Authenticated(user)); // Revert to authenticated if sign-out fails
      } else {
        emit(Unauthenticated()); // Should not happen if sign-out failed, but as fallback
      }
    } catch (e) {
      emit(AuthError('An unexpected error occurred during sign out: ${e.toString()}'));
      final user = _authRepository.currentUser;
       if (user != null) {
        emit(Authenticated(user)); // Revert to authenticated if sign-out fails
      } else {
        emit(Unauthenticated());
      }
    }
  }
}

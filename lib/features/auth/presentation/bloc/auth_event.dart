part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AppStarted extends AuthEvent {}

class LoginRequested extends AuthEvent {
  final String username;
  final String password;

  const LoginRequested({required this.username, required this.password});

  @override
  List<Object?> get props => [username, password];
}

class LogoutRequested extends AuthEvent {}

class ForgotPasswordRequested extends AuthEvent {
  final String email;

  const ForgotPasswordRequested({required this.email});

  @override
  List<Object?> get props => [email];
}

class ChangePasswordRequested extends AuthEvent {
  final String token;
  final String oldPassword;
  final String newPassword;

  const ChangePasswordRequested({
    required this.token,
    required this.oldPassword,
    required this.newPassword,
  });

  @override
  List<Object?> get props => [token, oldPassword, newPassword];
}

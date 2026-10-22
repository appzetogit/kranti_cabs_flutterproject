import '../data/models/user_model.dart';

enum AuthStatus { unknown, authenticating, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final String? error;

  const AuthState({required this.status, this.user, this.error});

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthState copyWith({AuthStatus? status, UserModel? user, String? error}) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }
}

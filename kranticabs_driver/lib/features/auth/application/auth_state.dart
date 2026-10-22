import '../data/driver_model.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final DriverModel? driver;

  const AuthState({this.status = AuthStatus.unknown, this.driver});

  AuthState copyWith({AuthStatus? status, DriverModel? driver}) {
    return AuthState(
      status: status ?? this.status,
      driver: driver ?? this.driver,
    );
  }
}

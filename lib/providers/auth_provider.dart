import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../authentication/services/auth_service.dart';
import '../models/app_user.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

class AuthStateNotifier extends StateNotifier<AppUser?> {
  final AuthService _authService;

  AuthStateNotifier(this._authService) : super(null) {
    _init();
  }

  Future<void> _init() async {
    state = await _authService.getCurrentUser();
  }

  Future<void> login(String email, String password) async {
    final user = await _authService.login(email, password);
    state = user;
  }

  Future<void> register(String name, String email, String password) async {
    await _authService.register(name, email, password);
  }

  Future<void> logout() async {
    await _authService.logout();
    state = null;
  }
}

final authProvider = StateNotifierProvider<AuthStateNotifier, AppUser?>((ref) {
  return AuthStateNotifier(ref.watch(authServiceProvider));
});

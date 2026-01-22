import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/database_service.dart';

class AuthState {
  final bool isAuthenticated;
  final String? username;
  final String? error;

  AuthState({
    this.isAuthenticated = false,
    this.username,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    String? username,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      username: username ?? this.username,
      error: error ?? this.error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final DatabaseService _databaseService;

  AuthNotifier(this._databaseService) : super(AuthState());

  Future<bool> login(String username, String password) async {
    try {
      state = state.copyWith(error: null);
      
      final isValid = await _databaseService.validateUser(username, password);
      
      if (isValid) {
        state = state.copyWith(
          isAuthenticated: true,
          username: username,
        );
        return true;
      } else {
        state = state.copyWith(
          error: 'Invalid credentials',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void logout() {
    state = AuthState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(DatabaseService.instance);
});


import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/app_user.dart';

const _tokenKey = 'auth_token';

/// Where the login token is kept. Real app: the phone's secure storage.
/// Tests replace it with an in-memory store.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) => _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}

class MemoryTokenStore implements TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Who is logged in. `null` means nobody. An error means the server
/// could not be reached while checking the saved login.
class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    String? token;
    try {
      token = await ref.read(tokenStoreProvider).read();
    } catch (_) {
      token = null;
    }
    if (token == null) return null;

    ref.read(authTokenProvider.notifier).set(token);

    try {
      final res = await ref.read(dioProvider).get('/auth/me');
      return AppUser.fromJson(res.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _clearToken();
        return null;
      }
      throw ApiError.from(e);
    }
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      await ref.read(dioProvider).post('/auth/register', data: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> verifyEmail({required String email, required String code}) async {
    try {
      final res = await ref
          .read(dioProvider)
          .post('/auth/verify-email', data: {'email': email, 'code': code});
      await _signIn(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> resendCode(String email) async {
    try {
      await ref.read(dioProvider).post('/auth/resend-code', data: {'email': email});
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await ref.read(dioProvider).post('/auth/forgot-password', data: {'email': email});
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> checkResetCode({required String email, required String code}) async {
    try {
      await ref
          .read(dioProvider)
          .post('/auth/check-reset-code', data: {'email': email, 'code': code});
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      await ref.read(dioProvider).post('/auth/reset-password', data: {
        'email': email,
        'code': code,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final res = await ref
          .read(dioProvider)
          .post('/auth/login', data: {'email': email, 'password': password});
      await _signIn(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Name and phone only. The server never changes email or role here.
  Future<void> updateProfile({required String name, required String phone}) async {
    try {
      final res = await ref
          .read(dioProvider)
          .patch('/auth/profile', data: {'name': name, 'phone': phone});
      state = AsyncData(AppUser.fromJson(res.data['data'] as Map<String, dynamic>));
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> changePassword({
    required String current,
    required String password,
    required String confirmation,
  }) async {
    try {
      await ref.read(dioProvider).post('/auth/change-password', data: {
        'current_password': current,
        'password': password,
        'password_confirmation': confirmation,
      });
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<void> logout() async {
    try {
      await ref.read(dioProvider).post('/auth/logout');
    } catch (_) {
      // Even if the server cannot be reached, log out on this phone.
    }
    await _clearToken();
    state = const AsyncData(null);
  }

  /// Forget the login on this phone without asking the server.
  /// For staff who cannot reach the server, for example outside the hotel network.
  Future<void> logoutLocal() async {
    await _clearToken();
    state = const AsyncData(null);
  }

  Future<void> _signIn(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    await ref.read(tokenStoreProvider).write(token);
    ref.read(authTokenProvider.notifier).set(token);
    state = AsyncData(AppUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<void> _clearToken() async {
    ref.read(authTokenProvider.notifier).set(null);
    try {
      await ref.read(tokenStoreProvider).delete();
    } catch (_) {}
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AppUser?>(AuthNotifier.new);

import 'package:angkor_stay/auth/auth_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/main.dart';
import 'package:angkor_stay/models/app_user.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the phone gets when the ngrok tunnel is switched off: ngrok itself answers with a 404 web
/// page (not our server) and marks it with the header `ngrok-error-code`.
DioException _tunnelOffline() {
  final request = RequestOptions(path: '/auth/me');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: 404,
      headers: Headers.fromMap({
        'ngrok-error-code': ['ERR_NGROK_3200'],
        'content-type': ['text/html'],
      }),
      data: '<!DOCTYPE html><html><body>The endpoint example.ngrok-free.dev is offline. (ERR_NGROK_3200)</body></html>',
    ),
  );
}

DioException _plainNotFound() {
  final request = RequestOptions(path: '/bookings/999');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(requestOptions: request, statusCode: 404, data: <String, dynamic>{}),
  );
}

class _OfflineTunnelAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => throw ApiError.from(_tunnelOffline());
}

void main() {
  group('an offline tunnel', () {
    test('says "Server not reachable", not a bare 404', () {
      final error = ApiError.from(_tunnelOffline());

      expect(error.message, contains('Server not reachable'));
      expect(error.message, isNot(contains('404')));
    });

    test('still keeps the status code for the code that needs it', () {
      expect(ApiError.from(_tunnelOffline()).statusCode, 404);
    });

    test('a real 404 from our own server keeps its normal message', () {
      final error = ApiError.from(_plainNotFound());

      expect(error.message, 'Something went wrong (404).');
      expect(error.message, isNot(contains('Server not reachable')));
    });

    test('a server message is still used when our server answers 404 with one', () {
      final request = RequestOptions(path: '/bookings/9');
      final error = ApiError.from(
        DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(requestOptions: request, statusCode: 404, data: {'message': 'Booking not found.'}),
        ),
      );

      expect(error.message, 'Booking not found.');
    });

    testWidgets('the Connection Issue screen shows "Server not reachable" instead of 404', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          retry: (retryCount, error) => null,
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
            authProvider.overrideWith(_OfflineTunnelAuth.new),
          ],
          child: const AngkorStayApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connection Issue'), findsOneWidget);
      expect(find.textContaining('Server not reachable'), findsOneWidget);
      expect(find.textContaining('404'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}

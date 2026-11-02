import 'package:dio/dio.dart';

/// A readable error from the API: one message, plus messages per form field.
class ApiError implements Exception {
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, String> fieldErrors;

  const ApiError(
    this.message, {
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
  });

  factory ApiError.from(Object error) {
    if (error is ApiError) return error;

    if (error is DioException) {
      final res = error.response;
      if (res == null) {
        return const ApiError('Cannot reach the server. Check the address and try again.');
      }

      final data = res.data;
      final fields = <String, String>{};
      String message = 'Something went wrong (${res.statusCode}).';
      String? code;

      if (data is Map) {
        if (data['message'] is String) message = data['message'] as String;
        if (data['code'] is String) code = data['code'] as String;
        final errors = data['errors'];
        if (errors is Map) {
          errors.forEach((key, value) {
            if (value is List && value.isNotEmpty) fields['$key'] = '${value.first}';
          });
        }
      }

      if (res.statusCode == 429) {
        message = 'Too many tries. Please wait a moment.';
      }

      return ApiError(message, statusCode: res.statusCode, code: code, fieldErrors: fields);
    }

    return ApiError('$error');
  }

  @override
  String toString() => message;
}

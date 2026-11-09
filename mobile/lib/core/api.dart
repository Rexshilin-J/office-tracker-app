import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? status;

  ApiException(this.message, {this.status});

  @override
  String toString() => message;
}

List<Map<String, dynamic>> asMapList(dynamic data) {
  if (data is! List) return [];
  return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Map<String, dynamic> asMap(dynamic data) {
  if (data is Map) return Map<String, dynamic>.from(data);
  return {};
}

class Api {
  Api._();
  static final Api instance = Api._();

  // Render Backend URL
  static const String _envUrl = String.fromEnvironment('API_URL');

  static const String _productionUrl =
      'https://office-tracker-app-u6j7.onrender.com';

  static String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;
    return _productionUrl;
  }

  String? token;
  int? userId;
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) =>
      _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final normalizedPath = path.startsWith('/') ? path : '/$path';

    var uri = Uri.parse('$baseUrl$normalizedPath');

    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Token $token';
    }

    final encoded = body == null ? null : jsonEncode(body);

    late http.Response res;

    try {
      switch (method) {
        case 'POST':
          res = await http
              .post(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 60));
          break;

        case 'PATCH':
          res = await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 60));
          break;

        case 'DELETE':
          res = await http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 60));
          break;

        default:
          res = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 60));
      }
    } catch (e) {
      throw ApiException(
        'Server-ku connect aagala ($baseUrl).\n'
        'Internet connection check pannunga. (${e.runtimeType})',
      );
    }

    dynamic data;

    if (res.bodyBytes.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        data = null;
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return data;
    }

    if (res.statusCode == 401 && token != null) {
      onUnauthorized?.call();
    }

    throw ApiException(
      _message(data, res.statusCode),
      status: res.statusCode,
    );
  }

  String _message(dynamic data, int code) {
    if (data is Map) {
      if (data['detail'] != null) {
        return data['detail'].toString();
      }

      final parts = <String>[];

      data.forEach((key, value) {
        final text = value is List
            ? value.join(', ')
            : value.toString();

        parts.add('$key: $text');
      });

      if (parts.isNotEmpty) return parts.join('\n');
    }

    if (data is List && data.isNotEmpty) {
      return data.join(', ');
    }

    return 'Request failed ($code)';
  }
}

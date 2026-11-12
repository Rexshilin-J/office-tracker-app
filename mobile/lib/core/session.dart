import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class Session extends ChangeNotifier {
  Session() {
    Api.instance.onUnauthorized = () {
      logout();
    };
  }

  Map<String, dynamic>? user;
  bool restoring = true;

  bool get loggedIn => user != null && Api.instance.token != null;
  String get username => (user?['username'] ?? '').toString();
  String get role => (user?['role'] ?? 'EMPLOYEE').toString();
  bool get isEmployee => role == 'EMPLOYEE';
  bool get isSuperAdmin => role == 'SUPER_ADMIN';

  /// What the server says this account may do (see accounts/permissions.py).
  bool can(String capability) {
    final caps = user?['capabilities'];
    return caps is Map && caps[capability] == true;
  }

  String get roleLabel {
    switch (role) {
      case 'SUPER_ADMIN':
        return 'Super Admin';
      case 'HR':
        return 'HR';
      case 'MANAGER':
        return 'Manager';
      default:
        return 'Employee';
    }
  }

  void _rememberUser() {
    Api.instance.userId = user?['id'] as int?;
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final rawUser = prefs.getString('user');

    if (token != null && rawUser != null) {
      Api.instance.token = token;
      try {
        // Validate the saved token and refresh profile.
        user = asMap(await Api.instance.get('/api/auth/me/'));
        _rememberUser();
        await prefs.setString('user', jsonEncode(user));
      } on ApiException catch (e) {
        if (e.status == 401 || e.status == 403) {
          Api.instance.token = null;
          user = null;
          await prefs.remove('token');
          await prefs.remove('user');
        } else {
          // Server unreachable: keep the saved login and try later.
          user = asMap(jsonDecode(rawUser));
          _rememberUser();
        }
      }
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final data = asMap(
      await Api.instance.post('/api/auth/login/', {
        'username': username,
        'password': password,
      }),
    );
    Api.instance.token = data['token'] as String;
    user = asMap(data['user']);
    _rememberUser();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', Api.instance.token!);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  Future<void> logout() async {
    // Ask the server to revoke this login token as well, so a copied or stolen
    // token stops working. Fire-and-forget: the request reads the token
    // synchronously right here, before it is cleared below, and a failure
    // (offline, already expired) must never stop the user from logging out.
    if (Api.instance.token != null) {
      unawaited(
        Api.instance.post('/api/auth/logout/').then<void>((_) {}, onError: (_) {}),
      );
    }
    Api.instance.token = null;
    Api.instance.userId = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    notifyListeners();
  }
}

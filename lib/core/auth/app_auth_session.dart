import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';

class AppAuthSession {
  static Future<String?> resolveApiBearerToken() async {
    final prefs = await SharedPreferences.getInstance();
    final staticToken = AppConstants.apiStaticToken.trim();
    final token = prefs.getString(AppConstants.tokenKey)?.trim();
    if (token != null && token.isNotEmpty && token != staticToken) {
      return token;
    }

    final sessionId = prefs.getString(AppConstants.sessionKey)?.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      return sessionId;
    }

    return null;
  }

  static Future<void> storeLoginData({
    required Map<String, dynamic> user,
    String? token,
    String? role,
    String? sessionId,
    String? webSessionCookie,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.userKey, jsonEncode(user));

    final effectiveRole = (role ?? user['role']?.toString() ?? '').trim();
    if (effectiveRole.isNotEmpty) {
      await prefs.setString(AppConstants.roleKey, effectiveRole);
    }

    final effectiveToken = (token ?? sessionId ?? '').trim();
    if (effectiveToken.isNotEmpty) {
      await prefs.setString(AppConstants.tokenKey, effectiveToken);
    }

    final effectiveSessionId = (sessionId ?? '').trim();
    if (effectiveSessionId.isNotEmpty) {
      await prefs.setString(AppConstants.sessionKey, effectiveSessionId);
    }

    final effectiveWebSessionCookie = (webSessionCookie ?? '').trim();
    if (effectiveWebSessionCookie.isNotEmpty) {
      await prefs.setString(
        AppConstants.webSessionCookieKey,
        effectiveWebSessionCookie,
      );
    }
  }

  static Future<Map<String, dynamic>?> getStoredUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(AppConstants.userKey);
    if (userJson == null || userJson.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(userJson);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  static Future<bool> hasActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final hasUser = (prefs.getString(AppConstants.userKey) ?? '').isNotEmpty;
    final hasSession =
        (prefs.getString(AppConstants.sessionKey) ?? '').trim().isNotEmpty;
    final staticToken = AppConstants.apiStaticToken.trim();
    final storedToken = (prefs.getString(AppConstants.tokenKey) ?? '').trim();
    final hasToken =
        storedToken.isNotEmpty && storedToken != staticToken;
    final hasWebSessionCookie =
        (prefs.getString(AppConstants.webSessionCookieKey) ?? '').trim().isNotEmpty;

    return hasUser && (hasSession || hasToken || hasWebSessionCookie);
  }

  static Future<String?> getStoredWebSessionCookie() async {
    final prefs = await SharedPreferences.getInstance();
    final cookie = prefs.getString(AppConstants.webSessionCookieKey)?.trim();
    if (cookie != null && cookie.isNotEmpty) {
      return cookie;
    }

    final sessionId = prefs.getString(AppConstants.sessionKey)?.trim();
    if (sessionId != null && sessionId.isNotEmpty) {
      return 'ci_session=$sessionId';
    }

    return null;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.userKey);
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.roleKey);
    await prefs.remove(AppConstants.sessionKey);
    await prefs.remove(AppConstants.webSessionCookieKey);
    await prefs.remove(AppConstants.lastSyncKey);
  }
}

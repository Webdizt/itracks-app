import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../config/constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> cacheUser(UserModel user);
  Future<UserModel?> getLastUser();
  Future<void> cacheToken(String token);
  Future<String?> getToken();
  Future<void> clearCache();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  final SharedPreferences sharedPreferences;

  AuthLocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<void> cacheUser(UserModel user) async {
    await sharedPreferences.setString(
      AppConstants.userKey,
      jsonEncode(user.toJson()),
    );
  }

  @override
  Future<UserModel?> getLastUser() async {
    final jsonString = sharedPreferences.getString(AppConstants.userKey);
    if (jsonString != null) {
      return UserModel.fromJson(jsonDecode(jsonString));
    }
    return null;
  }

  @override
  Future<void> cacheToken(String token) async {
    await sharedPreferences.setString(AppConstants.tokenKey, token);
  }

  @override
  Future<String?> getToken() async {
    return sharedPreferences.getString(AppConstants.tokenKey);
  }

  @override
  Future<void> clearCache() async {
    await sharedPreferences.remove(AppConstants.userKey);
    await sharedPreferences.remove(AppConstants.tokenKey);
    await sharedPreferences.remove(AppConstants.roleKey);
    await sharedPreferences.remove(AppConstants.sessionKey);
    await sharedPreferences.remove(AppConstants.lastSyncKey);
  }
}

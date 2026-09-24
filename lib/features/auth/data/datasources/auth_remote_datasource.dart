import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../config/constants.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<UserModel> login(String username, String password);
  Future<void> logout();
  Future<void> forgotPassword(String email);
  Future<void> changePassword(
      String token, String oldPassword, String newPassword);
  Future<bool> validateToken(String token);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiClient client;

  AuthRemoteDataSourceImpl({required this.client});

  @override
  Future<UserModel> login(String username, String password) async {
    try {
      final response = await client.post(AppConstants.login, data: {
        'username': username,
        'password': password,
      });

      if (response.statusCode == 200 && response.data['status'] == true) {
        return UserModel.fromJson(response.data['data']['user']);
      } else {
        throw ServerException(
            message: response.data['message'] ?? 'Login failed');
      }
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> logout() async {
    // Clear local token
    return;
  }

  @override
  Future<void> forgotPassword(String email) async {
    try {
      final response = await client.post(AppConstants.forgotPassword, data: {
        'username': email,
      });

      if (response.statusCode != 200) {
        throw ServerException(
            message: response.data['message'] ?? 'Failed to send reset email');
      }
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<void> changePassword(
      String token, String oldPassword, String newPassword) async {
    try {
      final response = await client.post('${AppConstants.changePassword}/$token', data: {
        'old_password': oldPassword,
        'new_password': newPassword,
      });

      if (response.statusCode != 200) {
        throw ServerException(
            message: response.data['message'] ?? 'Failed to change password');
      }
    } catch (e) {
      throw ServerException(message: e.toString());
    }
  }

  @override
  Future<bool> validateToken(String token) async {
    try {
      final response = await client.get('/validate-token');
      return response.statusCode == 200 && response.data['status'] == true;
    } catch (e) {
      return false;
    }
  }
}

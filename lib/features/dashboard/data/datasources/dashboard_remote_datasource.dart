// features/dashboard/data/datasources/dashboard_remote_datasource.dart

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/dashboard_stats_model.dart';

abstract class DashboardRemoteDataSource {
  Future<DashboardStatsModel> getDashboardStats();
  Future<Map<String, int>> getAssetStatsSimple();
  Future<List<Map<String, dynamic>>> getAssetStatsChart(); // ✅ Tetap List<Map>
  Future<List<dynamic>> getRecentActivity();
}

class DashboardRemoteDataSourceImpl implements DashboardRemoteDataSource {
  final ApiClient client;

  DashboardRemoteDataSourceImpl({required this.client});

  @override
  Future<DashboardStatsModel> getDashboardStats() async {
    try {
      final response = await client.get('/dashboard/stats');

      if (response.statusCode == 200 && response.data['status'] == true) {
        return DashboardStatsModel.fromApiJson(response.data['data']);
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load dashboard stats',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<Map<String, int>> getAssetStatsSimple() async {
    try {
      final response = await client.get('/stats/data');

      if (response.statusCode == 200 && response.data['status'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return data.map((key, value) => MapEntry(key, value as int));
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load stats',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAssetStatsChart() async {
    try {
      final response = await client.get('/stats/chart');

      if (response.statusCode == 200 && response.data['status'] == true) {
        return List<Map<String, dynamic>>.from(response.data['data']);
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load chart data',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<List<dynamic>> getRecentActivity() async {
    try {
      final response = await client.get('/dashboard/recent-activity');

      if (response.statusCode == 200 && response.data['status'] == true) {
        return response.data['data'] as List;
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load activities',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }
}

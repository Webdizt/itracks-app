import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/dashboard_stats.dart';

abstract class DashboardRepository {
  /// Get complete dashboard stats from API
  Future<Either<Failure, DashboardStats>> getDashboardStats();

  /// Get simple stats numbers only
  Future<Either<Failure, Map<String, int>>> getAssetStatsSimple();

  /// Get chart data
  Future<Either<Failure, List<Map<String, dynamic>>>> getAssetStatsChart();

  /// Get recent activities
  Future<Either<Failure, List<dynamic>>> getRecentActivity();
}

// features/dashboard/domain/repositories/dashboard_repository.dart

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/dashboard_stats.dart';

abstract class DashboardRepository {
  /// Get complete dashboard stats from API
  Future<Either<Failure, DashboardStats>> getDashboardStats();
  Future<Either<Failure, Map<String, int>>> getAssetStatsSimple();
  Future<Either<Failure, List<ChartData>>>
      getAssetStatsChart(); // ✅ Ganti dari List<Map<String, dynamic>>
  Future<Either<Failure, List<dynamic>>> getRecentActivity();
}

import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_datasource.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  DashboardRepositoryImpl({
    required this.remoteDataSource,
    required this.networkInfo,
  });

  @override
  Future<Either<Failure, DashboardStats>> getDashboardStats() async {
    if (await networkInfo.isConnected) {
      try {
        final stats = await remoteDataSource.getDashboardStats();
        return Right(stats);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message));
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection')); 
    }
  }

  @override
  Future<Either<Failure, Map<String, int>>> getAssetStatsSimple() async {
    if (await networkInfo.isConnected) {
      try {
        final stats = await remoteDataSource.getAssetStatsSimple();
        return Right(stats);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection')); 
    }
  }

  @override
  Future<Either<Failure, List<Map<String, dynamic>>>>
      getAssetStatsChart() async {
    if (await networkInfo.isConnected) {
      try {
        final data = await remoteDataSource.getAssetStatsChart();
        return Right(data);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection')); 
    }
  }

  @override
  Future<Either<Failure, List<dynamic>>> getRecentActivity() async {
    if (await networkInfo.isConnected) {
      try {
        final data = await remoteDataSource.getRecentActivity();
        return Right(data);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); 
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }
}

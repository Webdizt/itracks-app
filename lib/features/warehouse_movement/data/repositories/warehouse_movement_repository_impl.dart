import 'package:dartz/dartz.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/warehouse_movement.dart';
import '../../domain/entities/warehouse_movement_create_data.dart';
import '../../domain/entities/warehouse_movement_detail.dart';
import '../../domain/repositories/warehouse_movement_repository.dart';
import '../datasources/warehouse_movement_remote_datasource.dart';

class WarehouseMovementRepositoryImpl implements WarehouseMovementRepository {
  final WarehouseMovementRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  WarehouseMovementRepositoryImpl({
    required this.remoteDataSource,
    required this.networkInfo,
  });

  @override
  Future<Either<Failure, WarehouseMovementCreateData>> getCreateData() async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.getCreateData();
        return Right(result);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message));
      }
    }
    return const Left(NetworkFailure(message: 'No internet connection'));
  }

  @override
  Future<Either<Failure, List<WarehouseMovement>>> getMovementList({
    String? search,
    String? status,
    String? transactionType,
    int page = 1,
    int limit = 20,
  }) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.getMovementList(
          search: search,
          status: status,
          transactionType: transactionType,
          page: page,
          limit: limit,
        );
        return Right(result);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message));
      }
    }
    return const Left(NetworkFailure(message: 'No internet connection'));
  }

  @override
  Future<Either<Failure, WarehouseMovementDetail>> getMovementDetail(String uuid) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await remoteDataSource.getMovementDetail(uuid);
        return Right(result);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message));
      }
    }
    return const Left(NetworkFailure(message: 'No internet connection'));
  }
}

import 'package:dartz/dartz.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/inventory.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../datasources/inventory_remote_datasource.dart';
import '../../domain/entities/inventory_detail.dart';

class InventoryRepositoryImpl implements InventoryRepository {
  final InventoryRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;

  InventoryRepositoryImpl({
    required this.remoteDataSource,
    required this.networkInfo,
  });

  @override
  Future<Either<Failure, List<Inventory>>> getInventoryList({
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? category,
  }) async {
    if (await networkInfo.isConnected) {
      try {
        final items = await remoteDataSource.getInventoryList(
          page: page,
          limit: limit,
          search: search,
          status: status,
          category: category,
        );
        return Right(items);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message)); // ✅ Named parameter
      }
    } else {
      return const Left(NetworkFailure(
          message: 'No internet connection')); // ✅ Named parameter
    }
  }

  @override
  Future<Either<Failure, InventoryDetail?>> findInventoryByAssetCode(
      String assetCode) async {
    if (await networkInfo.isConnected) {
      try {
        // Step 1: Search inventory by asset code
        final result = await remoteDataSource.getInventoryList(
          search: assetCode,
          limit: 1,
        );

        // Step 2: If found, get full detail
        if (result.isNotEmpty) {
          final detail =
              await remoteDataSource.getInventoryDetail(result.first.id);
          return Right(detail);
        }

        // Not found
        return const Right(null);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message));
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }

  // ✅ BARU
  @override
  Future<Either<Failure, InventoryDetail>> getInventoryDetail(String id) async {
    try {
      final result = await remoteDataSource.getInventoryDetail(id);
      return Right(result);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> updateInventory(
      String id, Map<String, dynamic> data) async {
    try {
      await remoteDataSource.updateInventory(id, data);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, InventoryDetail?>> findInventoryBySn(String sn) async {
    if (await networkInfo.isConnected) {
      try {
        // Search di list dengan parameter search=SN
        final result = await remoteDataSource.getInventoryList(
          search: sn,
          limit: 1,
        );

        if (result.isEmpty) {
          return const Right(null); // Not found
        }

        // Ambil detail dari item pertama
        final detail =
            await remoteDataSource.getInventoryDetail(result.first.id);
        return Right(detail);
      } on ServerException catch (e) {
        return Left(ServerFailure(message: e.message));
      }
    } else {
      return const Left(NetworkFailure(message: 'No internet connection'));
    }
  }
}

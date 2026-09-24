import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/inventory.dart';
import '../entities/inventory_detail.dart';

abstract class InventoryRepository {
  Future<Either<Failure, List<Inventory>>> getInventoryList({
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? category,
  });

  Future<Either<Failure, InventoryDetail>> getInventoryDetail(String id);
  Future<Either<Failure, InventoryDetail?>> findInventoryByAssetCode(
      String assetCode);
  // ✅ BARU: Search by SN
  Future<Either<Failure, InventoryDetail?>> findInventoryBySn(String sn);

  Future<Either<Failure, void>> updateInventory(
      String id, Map<String, dynamic> data);
}

import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/warehouse_movement.dart';
import '../entities/warehouse_movement_create_data.dart';
import '../entities/warehouse_movement_detail.dart';

abstract class WarehouseMovementRepository {
  Future<Either<Failure, WarehouseMovementCreateData>> getCreateData();

  Future<Either<Failure, List<WarehouseMovement>>> getMovementList({
    String? search,
    String? status,
    String? transactionType,
    int page = 1,
    int limit = 20,
  });

  Future<Either<Failure, WarehouseMovementDetail>> getMovementDetail(String uuid);
}

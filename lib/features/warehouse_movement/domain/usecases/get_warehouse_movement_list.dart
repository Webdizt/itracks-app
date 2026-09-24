import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/warehouse_movement.dart';
import '../repositories/warehouse_movement_repository.dart';

class GetWarehouseMovementList {
  final WarehouseMovementRepository repository;

  GetWarehouseMovementList(this.repository);

  Future<Either<Failure, List<WarehouseMovement>>> call({
    String? search,
    String? status,
    String? transactionType,
    int page = 1,
    int limit = 20,
  }) {
    return repository.getMovementList(
      search: search,
      status: status,
      transactionType: transactionType,
      page: page,
      limit: limit,
    );
  }
}

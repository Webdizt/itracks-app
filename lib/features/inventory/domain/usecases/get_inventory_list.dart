import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/inventory.dart';
import '../repositories/inventory_repository.dart';

class GetInventoryList
    implements UseCase<List<Inventory>, GetInventoryListParams> {
  final InventoryRepository repository;

  GetInventoryList(this.repository);

  @override
  Future<Either<Failure, List<Inventory>>> call(
      GetInventoryListParams params) async {
    return await repository.getInventoryList(
      page: params.page,
      limit: params.limit,
      search: params.search,
      status: params.status,
      category: params.category,
    );
  }
}

class GetInventoryListParams {
  final int page;
  final int limit;
  final String? search;
  final String? status;
  final String? category;

  GetInventoryListParams({
    this.page = 1,
    this.limit = 20,
    this.search,
    this.status,
    this.category,
  });
}

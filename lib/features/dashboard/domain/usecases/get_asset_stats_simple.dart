import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/dashboard_repository.dart';

class GetAssetStatsSimple implements UseCase<Map<String, int>, NoParams> {
  final DashboardRepository repository;

  GetAssetStatsSimple(this.repository);

  @override
  Future<Either<Failure, Map<String, int>>> call(NoParams params) async {
    return await repository.getAssetStatsSimple();
  }
}

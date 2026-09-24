import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/project_job.dart';
import '../repositories/project_repository.dart';

class GetProjectJobListParams {
  final int page;
  final int limit;
  final String? search;

  const GetProjectJobListParams({
    this.page = 1,
    this.limit = 20,
    this.search,
  });
}

class GetProjectJobList extends UseCase<List<ProjectJob>, GetProjectJobListParams> {
  final ProjectRepository repository;

  GetProjectJobList(this.repository);

  @override
  Future<Either<Failure, List<ProjectJob>>> call(GetProjectJobListParams params) {
    return repository.getProjectJobList(
      page: params.page,
      limit: params.limit,
      search: params.search,
    );
  }
}

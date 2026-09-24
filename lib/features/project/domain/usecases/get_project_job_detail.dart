import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/project_job.dart';
import '../repositories/project_repository.dart';

class GetProjectJobDetail extends UseCase<ProjectJob, String> {
  final ProjectRepository repository;

  GetProjectJobDetail(this.repository);

  @override
  Future<Either<Failure, ProjectJob>> call(String id) {
    return repository.getProjectJobDetail(id);
  }
}

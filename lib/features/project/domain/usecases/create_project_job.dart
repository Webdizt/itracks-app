import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/project_job.dart';
import '../repositories/project_repository.dart';

class CreateProjectJob extends UseCase<ProjectJob, ProjectJob> {
  final ProjectRepository repository;

  CreateProjectJob(this.repository);

  @override
  Future<Either<Failure, ProjectJob>> call(ProjectJob params) {
    return repository.createProjectJob(params);
  }
}

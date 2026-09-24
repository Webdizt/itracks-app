import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/project_ref.dart';
import '../repositories/project_repository.dart';

class GetProjects extends UseCase<List<ProjectRef>, NoParams> {
  final ProjectRepository repository;

  GetProjects(this.repository);

  @override
  Future<Either<Failure, List<ProjectRef>>> call(NoParams params) {
    return repository.getProjects();
  }
}

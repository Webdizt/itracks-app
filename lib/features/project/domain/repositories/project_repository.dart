import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/project_job.dart';
import '../entities/project_ref.dart';

abstract class ProjectRepository {
  /// Fetch list of available projects from API.
  Future<Either<Failure, List<ProjectRef>>> getProjects();

  /// Create a new SSI-JOB (project job) on the backend.
  Future<Either<Failure, ProjectJob>> createProjectJob(ProjectJob job);

  /// Update an existing SSI-JOB.
  Future<Either<Failure, ProjectJob>> updateProjectJob(ProjectJob job);

  /// Get list of saved SSI-JOBs.
  Future<Either<Failure, List<ProjectJob>>> getProjectJobList({
    int page = 1,
    int limit = 20,
    String? search,
  });

  /// Get detail of a specific SSI-JOB.
  Future<Either<Failure, ProjectJob>> getProjectJobDetail(String id);
}

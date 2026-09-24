import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/project_job_model.dart';
import '../models/project_ref_model.dart';

abstract class ProjectRemoteDataSource {
  Future<List<ProjectRefModel>> getProjects();
  Future<ProjectJobModel> createProjectJob(Map<String, dynamic> data);
  Future<ProjectJobModel> updateProjectJob(String id, Map<String, dynamic> data);
  Future<List<ProjectJobModel>> getProjectJobList({
    int page = 1,
    int limit = 20,
    String? search,
  });
  Future<ProjectJobModel> getProjectJobDetail(String id);
}

class ProjectRemoteDataSourceImpl implements ProjectRemoteDataSource {
  final ApiClient client;

  ProjectRemoteDataSourceImpl({required this.client});

  @override
  Future<List<ProjectRefModel>> getProjects() async {
    try {
      final response = await client.get('/api/projects/list');

      if (response.statusCode == 200 && response.data['status'] == true) {
        final raw = response.data['data'];
        final List<dynamic> list = raw is List
            ? raw
            : (raw is Map<String, dynamic> && raw['items'] is List)
                ? raw['items']
                : (raw is Map<String, dynamic> && raw['projects'] is List)
                    ? raw['projects']
                    : [];
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => ProjectRefModel.fromJson(e))
            .toList();
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load projects',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<ProjectJobModel> createProjectJob(Map<String, dynamic> data) async {
    try {
      final response = await client.post('/api/ssi-jobs', data: data);

      if (response.statusCode == 200 && response.data['status'] == true) {
        final raw = response.data['data'];
        if (raw is! Map<String, dynamic>) {
          throw ServerException(message: 'Invalid response structure');
        }
        return ProjectJobModel.fromJson(raw);
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to create SSI-JOB',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<ProjectJobModel> updateProjectJob(
      String id, Map<String, dynamic> data) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      final response =
          await client.post('/api/ssi-jobs/update/$encodedId', data: data);

      if (response.statusCode == 200 && response.data['status'] == true) {
        final raw = response.data['data'];
        if (raw is! Map<String, dynamic>) {
          throw ServerException(message: 'Invalid response structure');
        }
        return ProjectJobModel.fromJson(raw);
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to update SSI-JOB',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<List<ProjectJobModel>> getProjectJobList({
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    try {
      final response = await client.get('/api/ssi-jobs', queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
      });

      if (response.statusCode == 200 && response.data['status'] == true) {
        final raw = response.data['data'];
        final List<dynamic> list = raw is List
            ? raw
            : (raw is Map<String, dynamic> && raw['items'] is List)
                ? raw['items']
                : [];
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => ProjectJobModel.fromJson(e))
            .toList();
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load SSI-JOB list',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<ProjectJobModel> getProjectJobDetail(String id) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await client.get('/api/ssi-jobs/detail/$encodedId');

      if (response.statusCode == 200 && response.data['status'] == true) {
        final raw = response.data['data'];
        if (raw is! Map<String, dynamic>) {
          throw ServerException(message: 'Invalid response structure');
        }
        return ProjectJobModel.fromJson(raw);
      } else {
        throw ServerException(
          message: response.data['message'] ?? 'Failed to load SSI-JOB detail',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }
}

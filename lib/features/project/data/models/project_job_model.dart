import '../../domain/entities/project_job.dart';
import '../../domain/entities/project_ref.dart';
import 'project_job_item_model.dart';
import 'project_ref_model.dart';

class ProjectJobModel extends ProjectJob {
  const ProjectJobModel({
    super.id,
    required super.jobNumber,
    required super.project,
    super.status,
    super.items,
    super.createdAt,
    super.updatedAt,
  });

  factory ProjectJobModel.fromJson(Map<String, dynamic> json) {
    final projectData = json['project'];
    final ProjectRef project = projectData is Map<String, dynamic>
        ? ProjectRefModel.fromJson(projectData)
        : ProjectRef(
            jobNumber: '${json['project_ref'] ?? json['job_number'] ?? ''}',
            client: '${json['client'] ?? '-'}',
            location: '${json['location'] ?? '-'}',
          );

    final rawItems = json['items'] ?? json['project_job_items'];
    final List<dynamic> itemsList = rawItems is List ? rawItems : [];

    return ProjectJobModel(
      id: json['id']?.toString() ?? json['encrypted_id']?.toString(),
      jobNumber: '${json['job_number'] ?? json['jobNumber'] ?? ''}',
      project: project,
      status: '${json['status'] ?? 'draft'}',
      items: itemsList
          .whereType<Map<String, dynamic>>()
          .map((e) => ProjectJobItemModel.fromJson(e))
          .toList(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse('${json['created_at']}')
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse('${json['updated_at']}')
          : null,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'job_number': jobNumber,
        'project': (project as ProjectRefModel?)?.toJson() ?? project.toJson(),
        'status': status,
        'items': items.map((e) => (e as ProjectJobItemModel).toJson()).toList(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}

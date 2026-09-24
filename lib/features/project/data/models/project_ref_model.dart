import '../../domain/entities/project_ref.dart';

class ProjectRefModel extends ProjectRef {
  const ProjectRefModel({
    required super.jobNumber,
    required super.client,
    required super.location,
    super.nextSequence,
  });

  factory ProjectRefModel.fromJson(Map<String, dynamic> json) {
    return ProjectRefModel(
      jobNumber: '${json['job_number'] ?? json['project_number'] ?? ''}',
      client: '${json['client'] ?? json['company_name'] ?? '-'}',
      location: '${json['location'] ?? '-'}',
      nextSequence:
          int.tryParse('${json['next_sequence'] ?? json['job_count'] ?? 1}') ?? 1,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'job_number': jobNumber,
        'client': client,
        'location': location,
        'next_sequence': nextSequence,
      };
}

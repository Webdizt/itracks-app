import 'package:equatable/equatable.dart';

class ProjectRef extends Equatable {
  final String jobNumber;
  final String client;
  final String location;
  final int nextSequence;

  const ProjectRef({
    required this.jobNumber,
    required this.client,
    required this.location,
    this.nextSequence = 1,
  });

  factory ProjectRef.fromJson(Map<String, dynamic> json) {
    return ProjectRef(
      jobNumber: '${json['job_number'] ?? json['project_number'] ?? ''}',
      client: '${json['client'] ?? json['company_name'] ?? '-'}',
      location: '${json['location'] ?? '-'}',
      nextSequence:
          int.tryParse('${json['next_sequence'] ?? json['job_count'] ?? 1}') ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'job_number': jobNumber,
        'client': client,
        'location': location,
        'next_sequence': nextSequence,
      };

  @override
  List<Object?> get props => [jobNumber, client, location, nextSequence];
}

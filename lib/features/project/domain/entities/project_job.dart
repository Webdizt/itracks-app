import 'package:equatable/equatable.dart';
import 'project_job_item.dart';
import 'project_ref.dart';

class ProjectJob extends Equatable {
  final String? id;
  final String jobNumber;
  final ProjectRef project;
  final String status;
  final List<ProjectJobItem> items;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProjectJob({
    this.id,
    required this.jobNumber,
    required this.project,
    this.status = 'draft',
    this.items = const [],
    this.createdAt,
    this.updatedAt,
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;
  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);

  ProjectJob copyWith({
    String? id,
    String? jobNumber,
    ProjectRef? project,
    String? status,
    List<ProjectJobItem>? items,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectJob(
      id: id ?? this.id,
      jobNumber: jobNumber ?? this.jobNumber,
      project: project ?? this.project,
      status: status ?? this.status,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'job_number': jobNumber,
        'project': project.toJson(),
        'status': status,
        'items': items.map((e) => e.toJson()).toList(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  @override
  List<Object?> get props =>
      [id, jobNumber, project, status, items, createdAt, updatedAt];
}

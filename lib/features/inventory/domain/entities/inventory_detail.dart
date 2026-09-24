import 'package:equatable/equatable.dart';

class InventoryDetail extends Equatable {
  final String id;
  final String assetCode;
  final String? brand;
  final String? model;
  final String? sn;
  final String? group;
  final String? categoryName;
  final String? department;
  final String? departmentName;
  final String? condition;
  final String? location;
  final String? locationName;
  final String? usage;
  final String? remarks;
  final String? photo;
  final String? createdByName;
  final String? updatedByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<InventoryHistory> history;
  final List<MaintenanceRecord> maintenance;
  final List<DocumentFile> documents;
  final int statusCode;

  const InventoryDetail({
    required this.id,
    required this.assetCode,
    this.brand,
    this.model,
    this.sn,
    this.group,
    this.categoryName,
    this.department,
    this.departmentName,
    this.condition,
    this.location,
    this.locationName,
    this.usage,
    this.remarks,
    this.photo,
    this.createdByName,
    this.updatedByName,
    this.createdAt,
    this.updatedAt,
    this.history = const [],
    this.maintenance = const [],
    this.documents = const [],
    this.statusCode = 0, 
  });

  @override
  List<Object?> get props => [
        id, assetCode, brand, model, sn, group, categoryName,
        department, departmentName, condition, location, locationName,
        usage, remarks, photo, createdByName, updatedByName,
        createdAt, updatedAt, history, maintenance, documents
      ];
}

class InventoryHistory extends Equatable {
  final String id;
  final String action;
  final String? oldLocationName;
  final String? newLocationName;
  final String? userName;
  final DateTime? createdAt;
  final String? notes;

  const InventoryHistory({
    required this.id,
    required this.action,
    this.oldLocationName,
    this.newLocationName,
    this.userName,
    this.createdAt,
    this.notes,
  });

  @override
  List<Object?> get props => [
        id, action, oldLocationName, newLocationName, 
        userName, createdAt, notes
      ];
}

class MaintenanceRecord extends Equatable {
  final String id;
  final String type;
  final DateTime? maintenanceDate;
  final String? description;
  final String? technicianName;
  final String? status;
  final double? cost;

  const MaintenanceRecord({
    required this.id,
    required this.type,
    this.maintenanceDate,
    this.description,
    this.technicianName,
    this.status,
    this.cost,
  });

  @override
  List<Object?> get props => [
        id, type, maintenanceDate, description, 
        technicianName, status, cost
      ];
}

class DocumentFile extends Equatable {
  final String id;
  final String fileName;
  final String fileType;
  final String fileUrl;
  final DateTime? uploadedAt;

  const DocumentFile({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.fileUrl,
    this.uploadedAt,
  });

  @override
  List<Object?> get props => [id, fileName, fileType, fileUrl, uploadedAt];
}
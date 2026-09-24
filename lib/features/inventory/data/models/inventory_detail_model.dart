import '../../domain/entities/inventory_detail.dart';

class InventoryDetailModel extends InventoryDetail {
  const InventoryDetailModel({
    required super.id,
    required super.assetCode,
    super.brand,
    super.model,
    super.sn,
    super.group,
    super.categoryName,
    super.department,
    super.departmentName,
    super.condition,
    super.location,
    super.locationName,
    super.usage,
    super.remarks,
    super.photo,
    super.createdByName,
    super.updatedByName,
    super.createdAt,
    super.updatedAt,
    super.history = const [],
    super.maintenance = const [],
    super.documents = const [],
    super.statusCode = 0,
  });

  factory InventoryDetailModel.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) {
      throw Exception('Empty JSON data');
    }

    // ✅ PANGGIL DENGAN NAMA CLASS
    final rawCondition = json['eq_condition'] ?? json['condition'];
    final statusCode = InventoryDetailModel._mapConditionToStatus(
      rawCondition?.toString(),
    );

    return InventoryDetailModel(
      id: '${json['id'] ?? ''}',
      assetCode: '${json['asset_code'] ?? json['assetCode'] ?? ''}',
      brand: json['brand']?.toString(),
      model: json['model']?.toString(),
      sn: (json['sn'] ?? json['serial_number'])?.toString(),
      group: (json['eq_group'] ?? json['group'])?.toString(),
      categoryName: json['category_name']?.toString(),
      department: json['department']?.toString(),
      departmentName: json['department_name']?.toString(),
      condition: (json['eq_condition'] ?? json['condition'])?.toString(),
      location: (json['eq_location'] ?? json['location'])?.toString(),
      locationName: json['location_name']?.toString(),
      usage: json['eq_usage']?.toString(),
      remarks: json['remarks']?.toString(),
      photo: json['photo']?.toString().trim(),
      createdByName: json['created_by_name']?.toString(),
      updatedByName: json['updated_by_name']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
      history: (json['history'] as List<dynamic>?)
              ?.map((e) {
                if (e is Map<String, dynamic>) {
                  return InventoryHistoryModel.fromJson(e);
                }
                return null;
              })
              .whereType<InventoryHistoryModel>()
              .toList() ??
          [],
      maintenance: (json['maintenance'] as List<dynamic>?)
              ?.map((e) {
                if (e is Map<String, dynamic>) {
                  return MaintenanceRecordModel.fromJson(e);
                }
                return null;
              })
              .whereType<MaintenanceRecordModel>()
              .toList() ??
          [],
      documents: (json['documents'] as List<dynamic>?)
              ?.map((e) {
                if (e is Map<String, dynamic>) {
                  return DocumentFileModel.fromJson(e);
                }
                return null;
              })
              .whereType<DocumentFileModel>()
              .toList() ??
          [],
      statusCode: statusCode, // ✅ SEKARANG SUDAH ADA
    );
  }

  static int _mapConditionToStatus(String? condition) {
    switch (condition?.toLowerCase()) {
      case 'good':
      case 'available':
        return 2; // Available
      case 'in use':
        return 1; // In Use
      case 'on board':
        return 3; // On Board
      default:
        return 0; // Unknown
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'asset_code': assetCode,
      'brand': brand,
      'model': model,
      'sn': sn,
      'eq_group': group,
      'category_name': categoryName,
      'department': department,
      'department_name': departmentName,
      'eq_condition': condition,
      'eq_location': location,
      'location_name': locationName,
      'eq_usage': usage,
      'remarks': remarks,
      'photo': photo,
      'created_by_name': createdByName,
      'updated_by_name': updatedByName,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class InventoryHistoryModel extends InventoryHistory {
  const InventoryHistoryModel({
    required super.id,
    required super.action,
    super.oldLocationName,
    super.newLocationName,
    super.userName,
    super.createdAt,
    super.notes,
  });

  factory InventoryHistoryModel.fromJson(Map<String, dynamic> json) {
    return InventoryHistoryModel(
      id: json['id']?.toString() ?? '',
      action: json['action'] ?? '',
      oldLocationName: json['old_location_name'],
      newLocationName: json['new_location_name'],
      userName: json['user_name'],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      notes: json['notes'],
    );
  }
}

class MaintenanceRecordModel extends MaintenanceRecord {
  const MaintenanceRecordModel({
    required super.id,
    required super.type,
    super.maintenanceDate,
    super.description,
    super.technicianName,
    super.status,
    super.cost,
  });

  factory MaintenanceRecordModel.fromJson(Map<String, dynamic> json) {
    return MaintenanceRecordModel(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? '',
      maintenanceDate: json['maintenance_date'] != null
          ? DateTime.tryParse(json['maintenance_date'])
          : null,
      description: json['description'],
      technicianName: json['technician_name'],
      status: json['status'],
      cost: json['cost'] != null
          ? double.tryParse(json['cost'].toString())
          : null,
    );
  }
}

class DocumentFileModel extends DocumentFile {
  const DocumentFileModel({
    required super.id,
    required super.fileName,
    required super.fileType,
    required super.fileUrl,
    super.uploadedAt,
  });

  factory DocumentFileModel.fromJson(Map<String, dynamic> json) {
    return DocumentFileModel(
      id: json['id']?.toString() ?? '',
      fileName: json['file_name'] ?? '',
      fileType: json['file_type'] ?? '',
      fileUrl: json['file_url'] ?? '',
      uploadedAt: json['uploaded_at'] != null
          ? DateTime.tryParse(json['uploaded_at'])
          : null,
    );
  }
}

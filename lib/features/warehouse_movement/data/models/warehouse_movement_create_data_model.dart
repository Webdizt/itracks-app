import '../../domain/entities/warehouse_movement_create_data.dart';

class WarehouseMovementOptionModel extends WarehouseMovementOption {
  const WarehouseMovementOptionModel({
    required super.id,
    required super.name,
  });

  factory WarehouseMovementOptionModel.fromJson(Map<String, dynamic> json) {
    return WarehouseMovementOptionModel(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? json['job_number'] ?? '-'}',
    );
  }
}

class WarehouseMovementCreateDataModel extends WarehouseMovementCreateData {
  const WarehouseMovementCreateDataModel({
    required super.transactionTypes,
    required super.purposes,
    required super.locations,
    required super.projects,
    super.requester,
  });

  factory WarehouseMovementCreateDataModel.fromJson(Map<String, dynamic> json) {
    List<WarehouseMovementOption> mapOptions(dynamic rows) {
      return (rows as List? ?? const [])
          .map((e) => WarehouseMovementOptionModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final requesterJson = json['requester'];
    return WarehouseMovementCreateDataModel(
      transactionTypes: mapOptions(json['transaction_types']),
      purposes: mapOptions(json['purposes']),
      locations: mapOptions(json['locations']),
      projects: mapOptions(json['projects']),
      requester: requesterJson is Map
          ? WarehouseMovementOptionModel.fromJson(Map<String, dynamic>.from(requesterJson))
          : null,
    );
  }
}

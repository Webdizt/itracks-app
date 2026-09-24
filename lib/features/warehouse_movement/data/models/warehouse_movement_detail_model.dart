import '../../domain/entities/warehouse_movement_detail.dart';
import 'warehouse_movement_item_model.dart';
import 'warehouse_movement_model.dart';

class WarehouseMovementLogModel extends WarehouseMovementLog {
  const WarehouseMovementLogModel({
    required super.action,
    required super.actionBy,
    required super.actionAt,
    super.notes,
  });

  factory WarehouseMovementLogModel.fromJson(Map<String, dynamic> json) {
    return WarehouseMovementLogModel(
      action: '${json['action'] ?? '-'}',
      actionBy: '${json['action_by'] ?? '-'}',
      actionAt: '${json['action_at'] ?? '-'}',
      notes: json['notes']?.toString(),
    );
  }
}

class WarehouseMovementDetailModel extends WarehouseMovementDetail {
  const WarehouseMovementDetailModel({
    required super.movement,
    required super.items,
    required super.logs,
  });

  factory WarehouseMovementDetailModel.fromJson(Map<String, dynamic> json) {
    return WarehouseMovementDetailModel(
      movement: WarehouseMovementModel.fromJson(
        Map<String, dynamic>.from(json['movement'] ?? const {}),
      ),
      items: (json['items'] as List? ?? const [])
          .map((e) => WarehouseMovementItemModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      logs: (json['logs'] as List? ?? const [])
          .map((e) => WarehouseMovementLogModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

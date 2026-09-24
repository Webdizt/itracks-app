import '../../domain/entities/warehouse_movement_item.dart';

class WarehouseMovementItemModel extends WarehouseMovementItem {
  const WarehouseMovementItemModel({
    required super.id,
    required super.itemType,
    required super.inventoryId,
    required super.itemName,
    super.assetCode,
    super.serialNumber,
    required super.qty,
    super.uom,
    super.currentLocationName,
    super.projectName,
  });

  factory WarehouseMovementItemModel.fromJson(Map<String, dynamic> json) {
    return WarehouseMovementItemModel(
      id: '${json['id'] ?? ''}',
      itemType: '${json['item_type'] ?? ''}',
      inventoryId: '${json['inventory_id'] ?? ''}',
      itemName: '${json['item_name'] ?? '-'}',
      assetCode: json['asset_code']?.toString(),
      serialNumber: json['serial_number']?.toString(),
      qty: double.tryParse('${json['qty'] ?? 0}') ?? 0,
      uom: json['uom']?.toString(),
      currentLocationName: json['current_location_name']?.toString(),
      projectName: json['project_name']?.toString(),
    );
  }
}

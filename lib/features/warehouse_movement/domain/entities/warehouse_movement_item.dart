import 'package:equatable/equatable.dart';

class WarehouseMovementItem extends Equatable {
  final String id;
  final String itemType;
  final String inventoryId;
  final String itemName;
  final String? assetCode;
  final String? serialNumber;
  final double qty;
  final String? uom;
  final String? currentLocationName;
  final String? projectName;

  const WarehouseMovementItem({
    required this.id,
    required this.itemType,
    required this.inventoryId,
    required this.itemName,
    this.assetCode,
    this.serialNumber,
    required this.qty,
    this.uom,
    this.currentLocationName,
    this.projectName,
  });

  @override
  List<Object?> get props => [
        id,
        itemType,
        inventoryId,
        itemName,
        assetCode,
        serialNumber,
        qty,
        uom,
        currentLocationName,
        projectName,
      ];
}

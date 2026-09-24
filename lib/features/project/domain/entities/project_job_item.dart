import 'package:equatable/equatable.dart';
import '../../../inventory/domain/entities/inventory_detail.dart';

class ProjectJobItem extends Equatable {
  final String? id;
  final String assetCode;
  final String assetName;
  final String serialNumber;
  final int qty;
  final String? inventoryId;

  const ProjectJobItem({
    this.id,
    required this.assetCode,
    required this.assetName,
    required this.serialNumber,
    required this.qty,
    this.inventoryId,
  });

  factory ProjectJobItem.fromDetail(InventoryDetail detail) {
    final parts = [detail.brand, detail.model, detail.group]
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .map((value) => value.trim())
        .toList();

    return ProjectJobItem(
      assetCode: detail.assetCode,
      assetName: parts.isEmpty ? 'Asset tanpa nama' : parts.join(' - '),
      serialNumber: detail.sn ?? '-',
      qty: 1,
      inventoryId: detail.id,
    );
  }

  ProjectJobItem copyWith({
    String? id,
    String? assetCode,
    String? assetName,
    String? serialNumber,
    int? qty,
    String? inventoryId,
  }) {
    return ProjectJobItem(
      id: id ?? this.id,
      assetCode: assetCode ?? this.assetCode,
      assetName: assetName ?? this.assetName,
      serialNumber: serialNumber ?? this.serialNumber,
      qty: qty ?? this.qty,
      inventoryId: inventoryId ?? this.inventoryId,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'asset_code': assetCode,
        'asset_name': assetName,
        'serial_number': serialNumber,
        'qty': qty,
        if (inventoryId != null) 'inventory_id': inventoryId,
      };

  @override
  List<Object?> get props =>
      [id, assetCode, assetName, serialNumber, qty, inventoryId];
}

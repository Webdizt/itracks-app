import '../../domain/entities/project_job_item.dart';

class ProjectJobItemModel extends ProjectJobItem {
  const ProjectJobItemModel({
    super.id,
    required super.assetCode,
    required super.assetName,
    required super.serialNumber,
    required super.qty,
    super.inventoryId,
  });

  factory ProjectJobItemModel.fromJson(Map<String, dynamic> json) {
    return ProjectJobItemModel(
      id: json['id']?.toString(),
      assetCode: '${json['asset_code'] ?? json['assetCode'] ?? ''}',
      assetName: '${json['asset_name'] ?? json['assetName'] ?? '-'}',
      serialNumber: '${json['serial_number'] ?? json['serialNumber'] ?? '-'}',
      qty: int.tryParse('${json['qty'] ?? 0}') ?? 0,
      inventoryId: json['inventory_id']?.toString() ??
          json['inventoryId']?.toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'asset_code': assetCode,
        'asset_name': assetName,
        'serial_number': serialNumber,
        'qty': qty,
        if (inventoryId != null) 'inventory_id': inventoryId,
      };
}

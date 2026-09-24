import '../../domain/entities/inventory.dart';

class InventoryModel extends Inventory {
  const InventoryModel({
    required super.id,
    required super.assetCode,
    super.brand,
    super.model,
    super.sn,
    super.group,
    super.department,
    super.condition,
    super.location,
    required super.statusCode,
    super.photo,
    super.createdDate,
  });

  factory InventoryModel.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status_code'] ?? json['statusCode'] ?? 0;
    return InventoryModel(
      id: '${json['id'] ?? ''}',
      assetCode: '${json['asset_code'] ?? json['assetCode'] ?? ''}',
      brand: json['brand']?.toString(),
      model: json['model']?.toString(),
      sn: (json['sn'] ?? json['serial_number'])?.toString(),
      group: (json['group'] ?? json['eq_group'])?.toString(),
      department: (json['department'] ?? json['department_name'])?.toString(),
      condition: (json['condition'] ?? json['eq_condition'])?.toString(),
      location: (json['location'] ?? json['location_name'])?.toString(),
      statusCode:
          rawStatus is int ? rawStatus : int.tryParse('$rawStatus') ?? 0,
      photo: json['photo']?.toString(),
      createdDate: json['created_date']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'asset_code': assetCode,
      'brand': brand,
      'model': model,
      'sn': sn,
      'group': group,
      'department': department,
      'condition': condition,
      'location': location,
      'status_code': statusCode,
      'photo': photo,
      'created_date': createdDate,
    };
  }
}

import '../../domain/entities/warehouse_movement.dart';

class WarehouseMovementModel extends WarehouseMovement {
  const WarehouseMovementModel({
    required super.uuid,
    required super.movementNumber,
    required super.transactionType,
    required super.transactionTypeText,
    required super.purpose,
    required super.purposeText,
    super.sourceLocationName,
    super.destinationLocationName,
    super.projectName,
    super.requesterName,
    required super.movementDate,
    required super.status,
    required super.statusText,
    super.notes,
    required super.itemCount,
  });

  factory WarehouseMovementModel.fromJson(Map<String, dynamic> json) {
    String text(List<String> keys, {String fallback = '-'}) {
      for (final key in keys) {
        final value = '${json[key] ?? ''}'.trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }
      return fallback;
    }

    return WarehouseMovementModel(
      uuid: text(['uuid', 'id'], fallback: ''),
      movementNumber: text(['movement_number', 'vm_number', 'number', 'code']),
      transactionType: text(['transaction_type', 'type'], fallback: ''),
      transactionTypeText: text(['transaction_type_text', 'transaction_type', 'type_text', 'type']),
      purpose: text(['purpose'], fallback: ''),
      purposeText: text(['purpose_text', 'purpose']),
      sourceLocationName: text(['source_location_name', 'source_name', 'from_location'], fallback: '-'),
      destinationLocationName: text(['destination_location_name', 'destination_name', 'to_location'], fallback: '-'),
      projectName: text(['project_name', 'job_number', 'office_name'], fallback: '-'),
      requesterName: text(['requester_name', 'created_by_name'], fallback: '-'),
      movementDate: text(['movement_date', 'date', 'created_at']),
      status: text(['status'], fallback: ''),
      statusText: text(['status_text', 'status']),
      notes: json['notes']?.toString(),
      itemCount: int.tryParse('${json['item_count'] ?? 0}') ?? 0,
    );
  }
}

import 'package:equatable/equatable.dart';

class WarehouseMovement extends Equatable {
  final String uuid;
  final String movementNumber;
  final String transactionType;
  final String transactionTypeText;
  final String purpose;
  final String purposeText;
  final String? sourceLocationName;
  final String? destinationLocationName;
  final String? projectName;
  final String? requesterName;
  final String movementDate;
  final String status;
  final String statusText;
  final String? notes;
  final int itemCount;

  const WarehouseMovement({
    required this.uuid,
    required this.movementNumber,
    required this.transactionType,
    required this.transactionTypeText,
    required this.purpose,
    required this.purposeText,
    this.sourceLocationName,
    this.destinationLocationName,
    this.projectName,
    this.requesterName,
    required this.movementDate,
    required this.status,
    required this.statusText,
    this.notes,
    required this.itemCount,
  });

  @override
  List<Object?> get props => [
        uuid,
        movementNumber,
        transactionType,
        transactionTypeText,
        purpose,
        purposeText,
        sourceLocationName,
        destinationLocationName,
        projectName,
        requesterName,
        movementDate,
        status,
        statusText,
        notes,
        itemCount,
      ];
}

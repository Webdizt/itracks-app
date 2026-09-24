import 'package:equatable/equatable.dart';

class WarehouseMovementOption extends Equatable {
  final String id;
  final String name;

  const WarehouseMovementOption({
    required this.id,
    required this.name,
  });

  @override
  List<Object?> get props => [id, name];
}

class WarehouseMovementCreateData extends Equatable {
  final List<WarehouseMovementOption> transactionTypes;
  final List<WarehouseMovementOption> purposes;
  final List<WarehouseMovementOption> locations;
  final List<WarehouseMovementOption> projects;
  final WarehouseMovementOption? requester;

  const WarehouseMovementCreateData({
    required this.transactionTypes,
    required this.purposes,
    required this.locations,
    required this.projects,
    this.requester,
  });

  @override
  List<Object?> get props => [
        transactionTypes,
        purposes,
        locations,
        projects,
        requester,
      ];
}

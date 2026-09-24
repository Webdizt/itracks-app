import 'package:equatable/equatable.dart';

import 'warehouse_movement.dart';
import 'warehouse_movement_item.dart';

class WarehouseMovementLog extends Equatable {
  final String action;
  final String actionBy;
  final String actionAt;
  final String? notes;

  const WarehouseMovementLog({
    required this.action,
    required this.actionBy,
    required this.actionAt,
    this.notes,
  });

  @override
  List<Object?> get props => [action, actionBy, actionAt, notes];
}

class WarehouseMovementDetail extends Equatable {
  final WarehouseMovement movement;
  final List<WarehouseMovementItem> items;
  final List<WarehouseMovementLog> logs;

  const WarehouseMovementDetail({
    required this.movement,
    required this.items,
    required this.logs,
  });

  @override
  List<Object?> get props => [movement, items, logs];
}

import 'package:equatable/equatable.dart';

abstract class InventoryDetailEvent extends Equatable {
  const InventoryDetailEvent();

  @override
  List<Object?> get props => [];
}

class LoadInventoryDetail extends InventoryDetailEvent {
  final String id;

  const LoadInventoryDetail({required this.id});

  @override
  List<Object?> get props => [id];
}

class UpdateInventoryDetail extends InventoryDetailEvent {
  final String id;
  final Map<String, dynamic> data;

  const UpdateInventoryDetail({required this.id, required this.data});

  @override
  List<Object?> get props => [id, data];
}

class RefreshInventoryDetail extends InventoryDetailEvent {
  const RefreshInventoryDetail();
}
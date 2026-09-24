import 'package:equatable/equatable.dart';
import '../../domain/entities/inventory_detail.dart';

abstract class InventoryDetailState extends Equatable {
  const InventoryDetailState();

  @override
  List<Object?> get props => [];
}

class InventoryDetailInitial extends InventoryDetailState {}

class InventoryDetailLoading extends InventoryDetailState {}

class InventoryDetailLoaded extends InventoryDetailState {
  final InventoryDetail detail;
  
  const InventoryDetailLoaded({required this.detail});
  
  @override
  List<Object?> get props => [detail];
}

class InventoryDetailError extends InventoryDetailState {
  final String message;

  const InventoryDetailError({required this.message});

  @override
  List<Object?> get props => [message];
}

class InventoryDetailUpdating extends InventoryDetailState {
  final InventoryDetail detail;
  
  const InventoryDetailUpdating({required this.detail});
  
  @override
  List<Object?> get props => [detail];
}

class InventoryDetailUpdateError extends InventoryDetailState {
  final InventoryDetail detail;
  final String message;
  
  const InventoryDetailUpdateError({
    required this.detail,
    required this.message,
  });
  
  @override
  List<Object?> get props => [detail, message];
}
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/inventory_detail.dart';
import '../../domain/repositories/inventory_repository.dart';

// ==================== EVENTS ====================
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

// ==================== STATES ====================
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
  const InventoryDetailUpdateError({required this.detail, required this.message});
  @override
  List<Object?> get props => [detail, message];
}

// ==================== BLOC ====================
class InventoryDetailBloc extends Bloc<InventoryDetailEvent, InventoryDetailState> {
  final InventoryRepository repository;

  InventoryDetailBloc({required this.repository}) : super(InventoryDetailInitial()) {
    on<LoadInventoryDetail>(_onLoadInventoryDetail);
    on<UpdateInventoryDetail>(_onUpdateInventoryDetail);
    on<RefreshInventoryDetail>(_onRefreshInventoryDetail);
  }

  Future<void> _onLoadInventoryDetail(
    LoadInventoryDetail event,
    Emitter<InventoryDetailState> emit,
  ) async {
    emit(InventoryDetailLoading());
    
    final Either<Failure, InventoryDetail> result = await repository.getInventoryDetail(event.id);
    
    result.fold(
      (failure) => emit(InventoryDetailError(message: failure.message)),
      (detail) => emit(InventoryDetailLoaded(detail: detail)),
    );
  }

  Future<void> _onUpdateInventoryDetail(
    UpdateInventoryDetail event,
    Emitter<InventoryDetailState> emit,
  ) async {
    final currentState = state;
    if (currentState is InventoryDetailLoaded) {
      emit(InventoryDetailUpdating(detail: currentState.detail));
      
      final result = await repository.updateInventory(event.id, event.data);
      
      result.fold(
        (failure) => emit(InventoryDetailUpdateError(
          detail: currentState.detail,
          message: failure.message,
        )),
        (_) => add(LoadInventoryDetail(id: event.id)),
      );
    }
  }

  Future<void> _onRefreshInventoryDetail(
    RefreshInventoryDetail event,
    Emitter<InventoryDetailState> emit,
  ) async {
    final currentState = state;
    String? currentId;
    
    if (currentState is InventoryDetailLoaded) {
      currentId = currentState.detail.id;
    } else if (currentState is InventoryDetailUpdateError) {
      currentId = currentState.detail.id;
    }
    
    if (currentId != null) {
      add(LoadInventoryDetail(id: currentId));
    }
  }
}
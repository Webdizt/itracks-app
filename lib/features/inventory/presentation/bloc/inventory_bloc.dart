import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../domain/entities/inventory.dart';
import '../../domain/usecases/get_inventory_list.dart';

// ==================== EVENTS ====================

abstract class InventoryEvent extends Equatable {
  const InventoryEvent();

  @override
  List<Object?> get props => [];
}

class LoadInventory extends InventoryEvent {
  final String? search;
  final String? status;
  final String? category;

  const LoadInventory({this.search, this.status, this.category});

  @override
  List<Object?> get props => [search, status, category];
}

class RefreshInventory extends InventoryEvent {}

// ==================== STATES ====================

abstract class InventoryState extends Equatable {
  const InventoryState();

  @override
  List<Object?> get props => [];
}

class InventoryInitial extends InventoryState {}

class InventoryLoading extends InventoryState {}

class InventoryLoaded extends InventoryState {
  final List<Inventory> items;

  const InventoryLoaded({required this.items});

  @override
  List<Object?> get props => [items];
}

class InventoryError extends InventoryState {
  final String message;

  const InventoryError({required this.message});

  @override
  List<Object?> get props => [message];
}

// ==================== BLOC ====================

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final GetInventoryList getInventoryList;

  InventoryBloc({required this.getInventoryList}) : super(InventoryInitial()) {
    on<LoadInventory>(_onLoadInventory);
    on<RefreshInventory>(_onRefreshInventory);
  }

  Future<void> _onLoadInventory(
    LoadInventory event,
    Emitter<InventoryState> emit,
  ) async {
    emit(InventoryLoading());
    final result = await getInventoryList(GetInventoryListParams(
      search: event.search,
      status: event.status,
      category: event.category,
    ));
    result.fold(
      (failure) => emit(InventoryError(message: failure.message)),
      (items) => emit(InventoryLoaded(items: items)),
    );
  }

  Future<void> _onRefreshInventory(
    RefreshInventory event,
    Emitter<InventoryState> emit,
  ) async {
    final currentState = state;
    if (currentState is InventoryLoaded) {
      emit(InventoryLoaded(items: currentState.items));
    } else {
      emit(InventoryLoading());
    }

    final result = await getInventoryList(GetInventoryListParams());
    result.fold(
      (failure) => emit(InventoryError(message: failure.message)),
      (items) => emit(InventoryLoaded(items: items)),
    );
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../../domain/usecases/get_dashboard_stats.dart';

// ==================== EVENTS ====================

abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

class LoadDashboard extends DashboardEvent {}

class RefreshDashboard extends DashboardEvent {}

// ==================== STATES ====================

abstract class DashboardState extends Equatable {
  const DashboardState();

  @override
  List<Object?> get props => [];
}

class DashboardInitial extends DashboardState {}

class DashboardLoading extends DashboardState {}

class DashboardRefreshing extends DashboardState {
  final DashboardStats stats;

  const DashboardRefreshing({required this.stats});

  @override
  List<Object?> get props => [stats];
}

class DashboardLoaded extends DashboardState {
  final DashboardStats stats;
  final String? errorMessage;

  const DashboardLoaded({
    required this.stats,
    this.errorMessage,
  });

  bool get hasRefreshError => errorMessage != null;

  @override
  List<Object?> get props => [stats, errorMessage];
}

class DashboardError extends DashboardState {
  final String message;

  const DashboardError({required this.message});

  @override
  List<Object?> get props => [message];
}

// ==================== BLOC ====================

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final GetDashboardStats getDashboardStats;

  DashboardBloc({
    required this.getDashboardStats,
  }) : super(DashboardInitial()) {
    on<LoadDashboard>(_onLoadDashboard);
    on<RefreshDashboard>(_onRefreshDashboard);
  }

  Future<void> _onLoadDashboard(
    LoadDashboard event,
    Emitter<DashboardState> emit,
  ) async {
    emit(DashboardLoading());
    final result = await getDashboardStats(const NoParams());
    result.fold(
      (failure) => emit(DashboardError(message: failure.message)),
      (stats) => emit(DashboardLoaded(stats: stats)),
    );
  }

  Future<void> _onRefreshDashboard(
    RefreshDashboard event,
    Emitter<DashboardState> emit,
  ) async {
    final currentState = state;
    if (currentState is DashboardLoaded) {
      emit(DashboardRefreshing(stats: currentState.stats));
    } else {
      emit(DashboardLoading());
    }

    final result = await getDashboardStats(const NoParams());
    result.fold(
      (failure) {
        if (currentState is DashboardLoaded) {
          emit(DashboardLoaded(
            stats: currentState.stats,
            errorMessage: failure.message,
          ));
        } else {
          emit(DashboardError(message: failure.message));
        }
      },
      (stats) => emit(DashboardLoaded(stats: stats)),
    );
  }
}

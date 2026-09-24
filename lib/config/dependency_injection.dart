import 'package:get_it/get_it.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================== CORE ====================
import '../core/network/api_client.dart';
import '../core/network/network_info.dart';
import 'package:dio/dio.dart';

// ==================== DASHBOARD ====================
import '../features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import '../features/dashboard/data/repositories/dashboard_repository_impl.dart';
import '../features/dashboard/domain/repositories/dashboard_repository.dart';
import '../features/dashboard/domain/usecases/get_dashboard_stats.dart';
import '../features/dashboard/presentation/bloc/dashboard_bloc.dart';

// ==================== INVENTORY ====================
import '../features/inventory/data/datasources/inventory_remote_datasource.dart';
import '../features/inventory/data/repositories/inventory_repository_impl.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/inventory/domain/usecases/get_inventory_list.dart';
import '../features/inventory/presentation/bloc/inventory_bloc.dart';
import '../features/inventory/presentation/bloc/inventory_detail_bloc.dart';
import '../features/inventory/presentation/bloc/inventory_scan_bloc.dart';
import '../features/warehouse_movement/data/datasources/warehouse_movement_remote_datasource.dart';
import '../features/warehouse_movement/data/repositories/warehouse_movement_repository_impl.dart';
import '../features/warehouse_movement/domain/repositories/warehouse_movement_repository.dart';
import '../features/warehouse_movement/domain/usecases/get_warehouse_movement_list.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // External
  sl.registerLazySingleton(() => Dio());
  sl.registerLazySingleton(() => InternetConnectionChecker());

  // Core
  sl.registerLazySingleton<NetworkInfo>(() => NetworkInfoImpl(sl()));
  sl.registerLazySingleton(() => ApiClient(networkInfo: sl()));

  // Features
  _initDashboard();
  _initWarehouseMovement();
  _initInventory(); // ✅ Panggil sekali saja
}

// ==================== DASHBOARD ====================
void _initDashboard() {
  // BLoC
  sl.registerFactory(() => DashboardBloc(getDashboardStats: sl()));

  // Use cases
  sl.registerLazySingleton(() => GetDashboardStats(sl()));

  // Repository
  sl.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(
      remoteDataSource: sl(),
      networkInfo: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<DashboardRemoteDataSource>(
    () => DashboardRemoteDataSourceImpl(client: sl()),
  );
}

// ==================== INVENTORY ====================
void _initInventory() {
  // BLoC
  sl.registerFactory(() => InventoryBloc(getInventoryList: sl()));
  sl.registerFactory(() => InventoryDetailBloc(repository: sl()));
  sl.registerFactory(() => InventoryScanBloc(repository: sl()));

  // Use cases
  sl.registerLazySingleton(() => GetInventoryList(sl()));

  // Repository - ✅ HANYA 1x DI SINI
  sl.registerLazySingleton<InventoryRepository>(
    () => InventoryRepositoryImpl(
      remoteDataSource: sl(),
      networkInfo: sl(),
    ),
  );

  // Data sources - ✅ HANYA 1x DI SINI
  sl.registerLazySingleton<InventoryRemoteDataSource>(
    () => InventoryRemoteDataSourceImpl(client: sl()),
  );
}

void _initWarehouseMovement() {
  sl.registerLazySingleton(() => GetWarehouseMovementList(sl()));

  sl.registerLazySingleton<WarehouseMovementRepository>(
    () => WarehouseMovementRepositoryImpl(
      remoteDataSource: sl(),
      networkInfo: sl(),
    ),
  );

  sl.registerLazySingleton<WarehouseMovementRemoteDataSource>(
    () => WarehouseMovementRemoteDataSourceImpl(client: sl()),
  );
}

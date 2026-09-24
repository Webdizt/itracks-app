import 'package:equatable/equatable.dart';
import '../../domain/entities/inventory_detail.dart';
import '../../domain/entities/qr_scan_result.dart';

abstract class InventoryScanState extends Equatable {
  const InventoryScanState();
  @override
  List<Object?> get props => [];
}

class InventoryScanInitial extends InventoryScanState {}

class InventoryScanLoading extends InventoryScanState {}

class InventoryScanSuccess extends InventoryScanState {
  final InventoryDetail detail;
  final QrScanResult qrResult;
  const InventoryScanSuccess({required this.detail, required this.qrResult});
  @override
  List<Object?> get props => [detail, qrResult];
}

class InventoryScanNotFound extends InventoryScanState {
  final String sn;
  const InventoryScanNotFound({required this.sn});
  @override
  List<Object?> get props => [sn];
}

class InventoryScanError extends InventoryScanState {
  final String message;
  const InventoryScanError({required this.message});
  @override
  List<Object?> get props => [message];
}

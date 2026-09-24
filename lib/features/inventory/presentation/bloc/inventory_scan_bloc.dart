import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/inventory_detail.dart';
import '../../domain/entities/qr_scan_result.dart';
import '../../domain/repositories/inventory_repository.dart';
import 'inventory_scan_event.dart'; // ✅ IMPORT, bukan part
import 'inventory_scan_state.dart'; // ✅ IMPORT, bukan part

class InventoryScanBloc extends Bloc<InventoryScanEvent, InventoryScanState> {
  final InventoryRepository repository;

  InventoryScanBloc({required this.repository})
      : super(InventoryScanInitial()) {
    on<QrCodeScanned>(_onQrCodeScanned);
    on<ResetScan>(_onResetScan);
  }

  Future<void> _onQrCodeScanned(
    QrCodeScanned event,
    Emitter<InventoryScanState> emit,
  ) async {
    emit(InventoryScanLoading());

    final qrResult = QrScanResult.fromRawData(event.rawData);

    if (!qrResult.isValid) {
      emit(const InventoryScanError(message: 'Invalid QR Code format'));
      return;
    }

    // ✅ Panggil method baru
    final result =
        await repository.findInventoryByAssetCode(qrResult.assetCode);

    result.fold(
      (failure) => emit(InventoryScanError(message: failure.message)),
      (detail) {
        if (detail == null) {
          emit(InventoryScanNotFound(sn: qrResult.assetCode));
        } else {
          emit(InventoryScanSuccess(detail: detail, qrResult: qrResult));
        }
      },
    );
  }

  void _onResetScan(ResetScan event, Emitter<InventoryScanState> emit) {
    emit(InventoryScanInitial());
  }
}

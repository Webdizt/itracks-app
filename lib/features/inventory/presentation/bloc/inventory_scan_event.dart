import 'package:equatable/equatable.dart';

abstract class InventoryScanEvent extends Equatable {
  const InventoryScanEvent();
  @override
  List<Object?> get props => [];
}

class QrCodeScanned extends InventoryScanEvent {
  final String rawData;
  const QrCodeScanned({required this.rawData});
  @override
  List<Object?> get props => [rawData];
}

class ResetScan extends InventoryScanEvent {
  const ResetScan();
}

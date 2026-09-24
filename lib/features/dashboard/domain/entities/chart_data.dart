import 'package:equatable/equatable.dart';

class ChartData extends Equatable {
  final String label;
  final double value;
  final dynamic date; // Tambahkan date

  const ChartData({
    required this.label,
    required this.value,
    this.date,
  });

  @override
  List<Object?> get props => [label, value, date];
}

import '../../domain/entities/chart_data.dart';

class ChartDataModel extends ChartData {
  ChartDataModel({
    required super.label,
    required super.value,
    super.date,
  });

  factory ChartDataModel.fromJson(Map<String, dynamic> json) {
    return ChartDataModel(
      label: json['label'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
      date: json['date'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'value': value,
      'date': date,
    };
  }
}

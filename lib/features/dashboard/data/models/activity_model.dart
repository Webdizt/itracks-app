import '../../domain/entities/activity.dart';

class ActivityModel extends Activity {
  ActivityModel({
    required super.action,
    required super.detail,
    required super.status,
    required super.page,
    required super.date,
  });

  factory ActivityModel.fromJson(Map<String, dynamic> json) {
    return ActivityModel(
      action: json['action'],
      detail: json['detail'],
      status: json['status'],
      page: json['page'],
      date: DateTime.parse(json['date']),
    );
  }
}

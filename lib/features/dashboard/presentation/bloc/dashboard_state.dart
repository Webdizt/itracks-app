import 'package:equatable/equatable.dart';

class DashboardStats extends Equatable {
  final int totalInventory;
  final int totalAssets;
  final int activeProjects;
  final int pendingPO;
  final int pendingDO;
  final List<RecentActivity>? recentActivities;
  final List<ChartData>? inventoryChart;

  const DashboardStats({
    required this.totalInventory,
    required this.totalAssets,
    required this.activeProjects,
    required this.pendingPO,
    required this.pendingDO,
    this.recentActivities,
    this.inventoryChart,
  });

  @override
  List<Object?> get props => [
        totalInventory,
        totalAssets,
        activeProjects,
        pendingPO,
        pendingDO,
        recentActivities,
        inventoryChart,
      ];
}

class RecentActivity extends Equatable {
  final String id;
  final String title;
  final String description;
  final dynamic timestamp;
  final ActivityType type;

  const RecentActivity({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.type,
  });

  @override
  List<Object?> get props => [id, title, description, timestamp, type];
}

enum ActivityType { inventory, asset, project, po, do_ }

class ChartData extends Equatable {
  final String label;
  final double value;
  final dynamic date;

  const ChartData({
    required this.label,
    required this.value,
    required this.date,
  });

  @override
  List<Object?> get props => [label, value, date];
}

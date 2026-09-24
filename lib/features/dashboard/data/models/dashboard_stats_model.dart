import '../../domain/entities/dashboard_stats.dart';

class DashboardStatsModel extends DashboardStats {
  const DashboardStatsModel({
    required super.totalInventory,
    required super.totalAssets,
    required super.activeProjects,
    required super.pendingPO,
    required super.pendingDO,
    super.recentActivities,
    super.inventoryChart,
  });

  /// Factory dari API /dashboard/stats
  factory DashboardStatsModel.fromApiJson(Map<String, dynamic> json) {
    final inventoryStats =
        json['inventory_stats'] as Map<String, dynamic>? ?? {};
    final projectStats = json['project_stats'] as Map<String, dynamic>? ?? {};
    final poDoStats = json['po_do_stats'] as Map<String, dynamic>? ?? {};

    return DashboardStatsModel(
      totalInventory: inventoryStats['total'] ?? 0,
      totalAssets: inventoryStats['available'] ?? 0,
      activeProjects: projectStats['active'] ?? 0,
      pendingPO: poDoStats['total_po'] ?? 0,
      pendingDO: poDoStats['total_do'] ?? 0,
      recentActivities: _parseRecentActivities(json['recent_items']),
      inventoryChart: null,
    );
  }

  static List<RecentActivity>? _parseRecentActivities(dynamic data) {
    if (data == null) return null;
    if (data is! List) return null;
    if (data.isEmpty) return null;

    return data.map((e) => _parseRecentActivity(e)).toList();
  }

  static RecentActivity _parseRecentActivity(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id']?.toString() ?? '',
      title: _extractTitle(json),
      description: json['detail'] ?? json['description'] ?? '',
      timestamp:
          json['date'] ?? json['created_date'] ?? DateTime.now().toString(),
      type: _parseActivityType(json['page'] ?? json['action'] ?? ''),
    );
  }

  static String _extractTitle(Map<String, dynamic> json) {
    final action = json['action']?.toString() ?? '';
    final page = json['page']?.toString() ?? '';

    if (action.isNotEmpty && page.isNotEmpty) {
      return '$action on $page';
    }
    if (action.isNotEmpty) {
      return action;
    }
    if (page.isNotEmpty) {
      return page;
    }
    return 'System Activity';
  }

  static ActivityType _parseActivityType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('inventory')) return ActivityType.inventory;
    if (lower.contains('asset')) return ActivityType.asset;
    if (lower.contains('project')) return ActivityType.project;
    if (lower.contains('po') || lower.contains('purchase'))
      return ActivityType.po;
    if (lower.contains('do') || lower.contains('delivery'))
      return ActivityType.do_;
    return ActivityType.inventory;
  }

  /// Untuk local cache
  factory DashboardStatsModel.fromJson(Map<String, dynamic> json) {
    return DashboardStatsModel(
      totalInventory: json['total_inventory'] ?? 0,
      totalAssets: json['total_assets'] ?? 0,
      activeProjects: json['active_projects'] ?? 0,
      pendingPO: json['pending_po'] ?? 0,
      pendingDO: json['pending_do'] ?? 0,
      recentActivities: json['recent_activities'] != null
          ? (json['recent_activities'] as List)
              .map((e) => _recentActivityFromJson(e))
              .toList()
          : null,
      inventoryChart: json['inventory_chart'] != null
          ? (json['inventory_chart'] as List)
              .map((e) => _chartDataFromJson(e))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_inventory': totalInventory,
      'total_assets': totalAssets,
      'active_projects': activeProjects,
      'pending_po': pendingPO,
      'pending_do': pendingDO,
      'recent_activities':
          recentActivities?.map((e) => _recentActivityToJson(e)).toList(),
      'inventory_chart':
          inventoryChart?.map((e) => _chartDataToJson(e)).toList(),
    };
  }

  static RecentActivity _recentActivityFromJson(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      timestamp: json['timestamp'],
      type: ActivityType.values.firstWhere(
        (t) => t.toString() == 'ActivityType.${json['type']}',
        orElse: () => ActivityType.inventory,
      ),
    );
  }

  static Map<String, dynamic> _recentActivityToJson(RecentActivity e) {
    return {
      'id': e.id,
      'title': e.title,
      'description': e.description,
      'timestamp': e.timestamp is DateTime
          ? (e.timestamp as DateTime).toIso8601String()
          : e.timestamp,
      'type': e.type.toString().split('.').last,
    };
  }

  static ChartData _chartDataFromJson(Map<String, dynamic> json) {
    return ChartData(
      label: json['label'],
      value: (json['value'] as num).toDouble(),
      date: json['date'],
    );
  }

  static Map<String, dynamic> _chartDataToJson(ChartData e) {
    return {
      'label': e.label,
      'value': e.value,
      'date':
          e.date is DateTime ? (e.date as DateTime).toIso8601String() : e.date,
    };
  }
}

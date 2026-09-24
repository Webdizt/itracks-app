import 'package:flutter/material.dart';

class AppConstants {
  // ==================== BASE CONFIGURATION ====================
  // Production API endpoint. Override for a local server with
  // --dart-define=API_BASE_URL=<url>.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dn.seascapesurveys.com',
  );
  static const String apiVersion = 'v1';
  static const int connectTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000; // 30 seconds
  static const int itemsPerPage = 20;

  // ==================== STORAGE KEYS ====================
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String roleKey = 'user_role';
  static const String sessionKey = 'sess_id';
  static const String webSessionCookieKey = 'web_session_cookie';
  static const String lastSyncKey = 'last_sync_time';
  static const String rememberedUsernameKey = 'remembered_username';

  // ==================== STATIC API TOKEN ====================
  // Supply a legacy bearer token only at build time. Never commit credentials
  // to source control: --dart-define=API_STATIC_TOKEN=<token>
  static const String apiStaticToken =
      String.fromEnvironment('API_STATIC_TOKEN');
  static const String defaultDnCompanyId = '2';
  static const String defaultDnCompanyName = 'PT. Seascape Surveys Indonesia';
  static const String defaultDnCompanyAcronym = 'SSI';

  // ==================== ROLES ====================
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';
  static const String roleWorkshop = 'workshop';
  static const String roleManager = 'manager';

  // ==================== ASSET STATUS CODES ====================
  static const int statusInUse = 1;
  static const int statusAvailable = 2;
  static const int statusOnBoard = 3;
  static const int statusFaulty = 0;

  // ==================== ASSET STATUS TEXT ====================
  static const String textInUse = 'In Use';
  static const String textAvailable = 'Available';
  static const String textOnBoard = 'On Board';
  static const String textFaulty = 'Faulty';

  // ==================== API ENDPOINTS - AUTHENTICATION ====================
  static const String login = '/api/auth/login';
  static const String forgotPassword = '/api/forgot_password';
  static const String checkResetCode = '/api/check/reset-password';
  static const String resetPassword = '/recover/password';
  static const String changePassword = '/api/change-password';
  static const String validateToken = '/validate-token';

  // ==================== API ENDPOINTS - DASHBOARD ====================
  static const String dashboardStats = '/dashboard/stats';
  static const String recentActivity = '/dashboard/recent-activity';
  static const String statsSimple = '/stats/data';
  static const String statsChart = '/stats/chart';

  // ==================== API ENDPOINTS - INVENTORY ====================
  static const String inventoryList = '/inventory/list';
  static const String inventoryData = '/inventory/data';
  static const String inventoryCreate = '/inventory/create';
  static const String inventoryDetail = '/inventory/detail';
  static const String inventoryUpdate = '/inventory/update';
  static const String inventoryDelete = '/inventory/delete';
  static const String inventoryScan = '/inventory/scan/qr';

  // ==================== API ENDPOINTS - ASSETS ====================
  static const String assetsList = '/assets/list';
  static const String assetsDetail = '/assets/detail';
  static const String assetsByStatus = '/assets/by-status';
  static const String assetsHistory = '/assets/history';

  // ==================== API ENDPOINTS - PROJECTS ====================
  static const String projectsList = '/projects/list';
  static const String projectsDetail = '/projects/detail';
  static const String projectsCreate = '/projects/create';
  static const String projectsUpdate = '/projects/update';
  static const String projectsAssignAsset = '/projects/assign-asset';
  static const String projectsRemoveAsset = '/projects/remove-asset';
  static const String projectsSearchAssets = '/projects/search-assets';
  static const String projectsScanAssign = '/projects/scan-assign';

  // ==================== API ENDPOINTS - PURCHASE ORDER (PO) ====================
  static const String poList = '/po/list';
  static const String poDetail = '/po/detail';
  static const String poCreate = '/po/create';
  static const String poUpdate = '/po/update';
  static const String poDelete = '/po/delete';

  // ==================== API ENDPOINTS - DELIVERY ORDER (DO) ====================
  static const String doList = '/do/list';
  static const String doDetail = '/do/detail';
  static const String doCreate = '/do/create';
  static const String doUpdate = '/do/update';
  static const String doConfirm = '/do/confirm';

  // ==================== API ENDPOINTS - PROFILE ====================
  static const String profileDetail = '/profile/detail';
  static const String profileUpdate = '/profile/update';
  static const String profileChangePassword = '/profile/change-password';
  static const String profileUploadPhoto = '/profile/upload-photo';

  // ==================== API ENDPOINTS - MASTER DATA ====================
  static const String inventoryFormData = '/inventory/form-data';
  static const String manufactures = '/inventory/manufactures';
  static const String models = '/inventory/models';
  static const String departments = '/master/departments';
  static const String locations = '/master/locations';
  static const String vendors = '/master/vendors';
  static const String conditions = '/master/conditions';

  // ==================== API ENDPOINTS - NOTIFICATIONS ====================
  static const String notifications = '/notifications';
  static const String markNotificationRead = '/notifications/read';

  // ==================== API ENDPOINTS - SYNC ====================
  static const String syncData = '/sync/data';

  // ==================== HELPER METHODS FOR DYNAMIC URLS ====================

  /// Build URL with ID parameter
  static String buildUrl(String endpoint, String id) {
    return '$endpoint/$id';
  }

  /// Build URL with multiple parameters
  static String buildUrlWithParams(
      String endpoint, Map<String, dynamic> params) {
    String url = endpoint;
    params.forEach((key, value) {
      url = url.replaceAll(':$key', value.toString());
    });
    return url;
  }

  /// Build manufactures URL with group ID
  static String manufacturesByGroup(String groupId) {
    return '$manufactures/$groupId';
  }

  /// Build models URL with group and manufacture IDs
  static String modelsByGroupAndManufacture(
      String groupId, String manufactureId) {
    return '$models/$groupId/$manufactureId';
  }

  /// Build inventory detail URL
  static String inventoryDetailUrl(String encryptedId) {
    return '$inventoryDetail/$encryptedId';
  }

  /// Build inventory update URL
  static String inventoryUpdateUrl(String encryptedId) {
    return '$inventoryUpdate/$encryptedId';
  }

  /// Build inventory delete URL
  static String inventoryDeleteUrl(String encryptedId) {
    return '$inventoryDelete/$encryptedId';
  }

  /// Build project detail URL
  static String projectDetailUrl(String encryptedId) {
    return '$projectsDetail/$encryptedId';
  }

  /// Build project update URL
  static String projectUpdateUrl(String encryptedId) {
    return '$projectsUpdate/$encryptedId';
  }

  /// Build PO detail URL
  static String poDetailUrl(String encryptedId) {
    return '$poDetail/$encryptedId';
  }

  /// Build PO update URL
  static String poUpdateUrl(String encryptedId) {
    return '$poUpdate/$encryptedId';
  }

  /// Build PO delete URL
  static String poDeleteUrl(String encryptedId) {
    return '$poDelete/$encryptedId';
  }

  /// Build DO detail URL
  static String doDetailUrl(String encryptedId) {
    return '$doDetail/$encryptedId';
  }

  /// Build DO update URL
  static String doUpdateUrl(String encryptedId) {
    return '$doUpdate/$encryptedId';
  }

  /// Build DO confirm URL
  static String doConfirmUrl(String encryptedId) {
    return '$doConfirm/$encryptedId';
  }

  /// Build assets by status URL
  static String assetsByStatusUrl(String status) {
    return '$assetsByStatus/$status';
  }

  /// Build assets history URL
  static String assetsHistoryUrl(String encryptedId) {
    return '$assetsHistory/$encryptedId';
  }

  /// Build change password URL with token
  static String changePasswordUrl(String token) {
    return '$changePassword/$token';
  }

  /// Build check reset code URL
  static String checkResetCodeUrl(String code) {
    return '$checkResetCode/$code';
  }

  /// Build reset password URL
  static String resetPasswordUrl(String code) {
    return '$resetPassword/$code';
  }

  /// Build notifications URL with token
  static String notificationsUrl(String token) {
    return '$notifications/$token';
  }

  /// Build mark notification read URL
  static String markNotificationReadUrl(String notificationId) {
    return '$markNotificationRead/$notificationId';
  }

  /// Get status text from status code
  static String getStatusText(int statusCode) {
    switch (statusCode) {
      case statusInUse:
        return textInUse;
      case statusAvailable:
        return textAvailable;
      case statusOnBoard:
        return textOnBoard;
      case statusFaulty:
        return textFaulty;
      default:
        return 'Unknown';
    }
  }

  /// Get status color from status code
  static Color getStatusColor(int statusCode) {
    switch (statusCode) {
      case statusInUse:
        return AppColors.info;
      case statusAvailable:
        return AppColors.success;
      case statusOnBoard:
        return AppColors.warning;
      case statusFaulty:
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Get status light color from status code
  static Color getStatusLightColor(int statusCode) {
    switch (statusCode) {
      case statusInUse:
        return AppColors.infoLight;
      case statusAvailable:
        return AppColors.successLight;
      case statusOnBoard:
        return AppColors.warningLight;
      case statusFaulty:
        return AppColors.errorLight;
      default:
        return AppColors.surfaceVariant;
    }
  }
}

class AppColors {
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color accent = Color(0xFFEC4899);
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color glassWhite = Color(0x80FFFFFF);
  static const Color glassBlack = Color(0x80000000);
  static const Color glassPrimary = Color(0x206366F1);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textInverse = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);
  static const Color shadowLight = Color(0x1A000000);
  static const Color shadowMedium = Color(0x33000000);
  static const Color shadowPrimary = Color(0x406366F1);
}

// ✅ UKURAN SHADOW TETAP, TIDAK DIUBAH
class AppShadows {
  static BoxShadow get small => BoxShadow(
        color: AppColors.shadowLight,
        blurRadius: 8,
        offset: const Offset(0, 2),
      );
  static BoxShadow get medium => BoxShadow(
        color: AppColors.shadowMedium,
        blurRadius: 16,
        offset: const Offset(0, 4),
      );
  static BoxShadow get large => BoxShadow(
        color: AppColors.shadowMedium,
        blurRadius: 24,
        offset: const Offset(0, 8),
      );
  static BoxShadow get primary => BoxShadow(
        color: AppColors.shadowPrimary,
        blurRadius: 20,
        offset: const Offset(0, 8),
      );
}

// ✅ RADIUS TETAP
class AppRadius {
  static double xs = 8;
  static double sm = 12;
  static double md = 16;
  static double lg = 24;
  static double xl = 32;
  static double xxl = 48;
  static double circular = 999;
}

// ✅ ANIMASI TETAP, TIDAK DIUBAH
class AppAnimations {
  static Duration get fast => const Duration(milliseconds: 200);
  static Duration get normal => const Duration(milliseconds: 300);
  static Duration get slow => const Duration(milliseconds: 500);
  static Curve get easeOut => Curves.easeOutCubic;
  static Curve get easeInOut => Curves.easeInOutCubic;
  static Curve get bounce => Curves.elasticOut;
  static Curve get spring => Curves.fastOutSlowIn;
}

// ==================== EXTENSIONS FOR EASIER API ACCESS ====================
extension ApiEndpoints on AppConstants {
  // Quick access to full URLs
  static String get fullBaseUrl => '${AppConstants.baseUrl}';

  // Auth URLs
  static String get loginUrl => '${AppConstants.baseUrl}${AppConstants.login}';
  static String get forgotPasswordUrl =>
      '${AppConstants.baseUrl}${AppConstants.forgotPassword}';

  // Dashboard URLs
  static String get dashboardStatsUrl =>
      '${AppConstants.baseUrl}${AppConstants.dashboardStats}';

  // Inventory URLs
  static String get inventoryListUrl =>
      '${AppConstants.baseUrl}${AppConstants.inventoryList}';
  static String get inventoryCreateUrl =>
      '${AppConstants.baseUrl}${AppConstants.inventoryCreate}';
  static String get inventoryScanUrl =>
      '${AppConstants.baseUrl}${AppConstants.inventoryScan}';

  // Project URLs
  static String get projectsListUrl =>
      '${AppConstants.baseUrl}${AppConstants.projectsList}';
  static String get projectsAssignUrl =>
      '${AppConstants.baseUrl}${AppConstants.projectsAssignAsset}';
  static String get projectsScanAssignUrl =>
      '${AppConstants.baseUrl}${AppConstants.projectsScanAssign}';

  // PO URLs
  static String get poListUrl =>
      '${AppConstants.baseUrl}${AppConstants.poList}';
  static String get poCreateUrl =>
      '${AppConstants.baseUrl}${AppConstants.poCreate}';

  // DO URLs
  static String get doListUrl =>
      '${AppConstants.baseUrl}${AppConstants.doList}';
  static String get doCreateUrl =>
      '${AppConstants.baseUrl}${AppConstants.doCreate}';

  // Profile URLs
  static String get profileDetailUrl =>
      '${AppConstants.baseUrl}${AppConstants.profileDetail}';
  static String get profileUpdateUrl =>
      '${AppConstants.baseUrl}${AppConstants.profileUpdate}';

  // Master Data URLs
  static String get formDataUrl =>
      '${AppConstants.baseUrl}${AppConstants.inventoryFormData}';
  static String get departmentsUrl =>
      '${AppConstants.baseUrl}${AppConstants.departments}';
  static String get locationsUrl =>
      '${AppConstants.baseUrl}${AppConstants.locations}';
  static String get vendorsUrl =>
      '${AppConstants.baseUrl}${AppConstants.vendors}';
}

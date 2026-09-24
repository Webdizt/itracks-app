// lib/core/utils/role_checker.dart
class RoleChecker {
  static bool canAccessInventory(String role) =>
      ['admin', 'user', 'workshop'].contains(role);

  static bool canEditPO(String role) => ['admin', 'user'].contains(role);

  static bool canDeleteData(String role) => role == 'admin';

  static bool canApproveDO(String role) => ['admin', 'workshop'].contains(role);
}

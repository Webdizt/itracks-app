import 'package:flutter/material.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/dashboard/presentation/pages/dashboard_page.dart';
import '../features/inventory/presentation/pages/inventory_page.dart';
import '../features/inventory/presentation/pages/inventory_detail_page.dart'; // ✅ TAMBAH
import '../features/asset/presentation/pages/asset_page.dart';
import '../features/dn/presentation/pages/dn_page.dart';
import '../features/project/presentation/pages/project_page.dart';
import '../features/po/presentation/pages/po_page.dart';
import '../features/do/presentation/pages/do_page.dart';
import '../features/profile/presentation/pages/profile_page.dart';
import '../shared/widgets/main_scaffold.dart';

class AppRoutes {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(builder: (_) => const LoginPage());
      case '/home':
        return MaterialPageRoute(builder: (_) => const MainScaffold());
      case '/dashboard':
        return MaterialPageRoute(builder: (_) => const DashboardPage());
      case '/inventory':
        return MaterialPageRoute(builder: (_) => const InventoryPage());
      case '/inventory/detail':
        final args = settings.arguments as String?;
        return MaterialPageRoute(
          builder: (_) => InventoryDetailPage(inventoryId: args ?? ''), // ✅ SUDAH ADA
        );
      case '/assets':
        return MaterialPageRoute(builder: (_) => const AssetPage());
      case '/projects':
        return MaterialPageRoute(builder: (_) => const ProjectPage());
      case '/po':
        return MaterialPageRoute(builder: (_) => const POPage());
      case '/do':
        return MaterialPageRoute(builder: (_) => const DOPage());
      case '/dn':
        return MaterialPageRoute(builder: (_) => const DnPage());
      case '/profile':
        return MaterialPageRoute(builder: (_) => const ProfilePage());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('Route ${settings.name} not found')),
          ),
        );
    }
  }
}


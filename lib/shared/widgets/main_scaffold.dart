import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/barcode/presentation/pages/scan_page.dart';
import '../../features/dn/presentation/pages/dn_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/warehouse_movement/presentation/pages/wm_list_page.dart';
import 'modern_bottom_nav.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  int _wmRefreshToken = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardPage(),
      WarehouseMovementListPage(refreshToken: _wmRefreshToken),
      ScanPage(isActive: _currentIndex == 2),
      const DnPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: true, // ✅ Tambah ini untuk handle keyboard
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      extendBody: true, // ✅ Penting untuk floating bottom nav
      bottomNavigationBar: ModernBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 1) {
              _wmRefreshToken++;
            }
          });
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../config/constants.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../auth/presentation/pages/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final userData = await AppAuthSession.getStoredUserData();
    if (!mounted) {
      return;
    }
    setState(() {
      _userData = userData;
    });
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text(
              'The login session will be removed from this device. Continue signing out?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) {
      return;
    }

    setState(() {
      _loggingOut = true;
    });

    await AppAuthSession.clear();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName =
        (_userData?['name']?.toString().trim().isNotEmpty ?? false)
            ? _userData!['name'].toString()
            : 'Seascape User';
    final displayRole =
        (_userData?['role']?.toString().trim().isNotEmpty ?? false)
            ? _userData!['role'].toString()
            : 'User';
    final displayUsername =
        (_userData?['username']?.toString().trim().isNotEmpty ?? false)
            ? _userData!['username'].toString()
            : 'Belum ada sesi aktif';

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(displayName, displayRole, displayUsername)),
          SliverToBoxAdapter(child: _buildQuickLogout()),
          SliverToBoxAdapter(child: _buildMenuSection()),
        ],
      ),
    );
  }

  Widget _buildHeader(String displayName, String displayRole, String displayUsername) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E5FD8), Color(0xFF37A2E7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28.r),
          bottomRight: Radius.circular(28.r),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            CircleAvatar(
              radius: 46.r,
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 44.r, color: const Color(0xFF0E5FD8)),
            ),
            SizedBox(height: 16.h),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999.r),
              ),
              child: Text(
                displayRole,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              displayUsername,
              style: TextStyle(
                fontSize: 13.sp,
                color: Colors.white.withOpacity(0.92),
              ),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickLogout() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: const Icon(Icons.logout_rounded, color: AppColors.error),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Logout dari perangkat ini',
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'Remove the local user, token, and session for a clean sign-in.',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            _loggingOut
                ? SizedBox(
                    width: 22.w,
                    height: 22.w,
                    child: const CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : TextButton(
                    onPressed: _confirmLogout,
                    child: const Text('Logout'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuSection() {
    final menus = [
      _MenuItem('Edit Profile', Icons.edit_outlined, () {}),
      _MenuItem('Ganti Password', Icons.lock_outline_rounded, () {}),
      _MenuItem('Notifikasi', Icons.notifications_none_rounded, () {}),
      _MenuItem('Bantuan', Icons.help_outline_rounded, () {}),
      _MenuItem('Tentang Aplikasi', Icons.info_outline_rounded, () {}),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
      child: Column(
        children: menus.map(_buildMenuTile).toList(),
      ),
    );
  }

  Widget _buildMenuTile(_MenuItem menu) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 4.h),
        leading: Container(
          width: 42.w,
          height: 42.w,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Icon(menu.icon, color: const Color(0xFF0E5FD8)),
        ),
        title: Text(
          menu.title,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 16.sp,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: menu.onTap,
      ),
    );
  }
}

class _MenuItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  _MenuItem(this.title, this.icon, this.onTap);
}

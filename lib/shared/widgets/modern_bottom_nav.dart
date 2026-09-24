import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/constants.dart';

class ModernBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const ModernBottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final items = [
      _NavItem(Icons.home_rounded, Icons.home_outlined, 'Home'),
      _NavItem(
          Icons.inventory_2_rounded, Icons.inventory_2_outlined, 'WM'),
      _NavItem(
          Icons.qr_code_scanner_rounded, Icons.qr_code_scanner_rounded, 'Scan',
          isCenter: true),
      _NavItem(Icons.local_shipping_rounded, Icons.local_shipping_outlined, 'DN'),
      _NavItem(Icons.person_rounded, Icons.person_outlined, 'Profile'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.fromLTRB(10.w, 6.h, 10.w, 8.h),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppRadius.xl),
            topRight: Radius.circular(AppRadius.xl),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowMedium,
              blurRadius: 18,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = currentIndex == index;

            if (item.isCenter) {
              return GestureDetector(
                onTap: () => onTap(index),
                child: Container(
                  width: 56.w,
                  height: 56.w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    item.activeIcon,
                    color: Colors.white,
                    size: 28.r,
                  ),
                ),
              );
            }

            return GestureDetector(
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: AppAnimations.fast,
                curve: AppAnimations.easeOut,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: AppAnimations.fast,
                      child: Icon(
                        isSelected ? item.activeIcon : item.inactiveIcon,
                        key: ValueKey(isSelected),
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textTertiary,
                        size: 24.r,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final bool isCenter;

  _NavItem(this.activeIcon, this.inactiveIcon, this.label,
      {this.isCenter = false});
}

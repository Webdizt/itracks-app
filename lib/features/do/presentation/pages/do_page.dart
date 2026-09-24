import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/constants.dart';

class DOPage extends StatelessWidget {
  const DOPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Delivery Order'),
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: EdgeInsets.all(16.w),
        itemCount: 5,
        itemBuilder: (context, index) {
          return _buildDOCard(index);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'do_page_fab',
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('Buat DO'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildDOCard(int index) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DO-2024-${1000 + index}',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              _buildStatusBadge(index % 2 == 0 ? 'Delivered' : 'Pending'),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            'Project: Installation Site ${index + 1}',
            style: TextStyle(
              fontSize: 14.sp,
              color: AppColors.textSecondary, // ✅ Perbaikan: bukan textTertiary
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'Items: ${index + 2} equipment',
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColors
                  .textTertiary, // ✅ Perbaikan: textTertiary bukan textTertiary
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 14.r,
                color: AppColors
                    .textTertiary, // ✅ Perbaikan: textTertiary bukan textTertiary
              ),
              SizedBox(width: 4.w),
              Text(
                '20 Mar 2024',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors
                      .textTertiary, // ✅ Perbaikan: textTertiary bukan textTertiary
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = status == 'Delivered' ? AppColors.success : AppColors.warning;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

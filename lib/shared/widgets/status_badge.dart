import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/constants.dart';

enum StatusType {
  success,
  warning,
  error,
  info,
  pending,
}

class StatusBadge extends StatelessWidget {
  final String text;
  final StatusType type;
  final bool isFilled;

  const StatusBadge({
    Key? key,
    required this.text,
    this.type = StatusType.info,
    this.isFilled = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = _getColors();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color:
            isFilled ? colors.background : colors.background.withOpacity(0.1),
        // ✅ PERBAIKAN: Gunakan BorderRadius.circular dengan nilai double
        borderRadius: BorderRadius.circular(20.r), // 20.r adalah double
        border: isFilled ? null : Border.all(color: colors.border, width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.text,
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  _BadgeColors _getColors() {
    switch (type) {
      case StatusType.success:
        return _BadgeColors(
          background: AppColors.success,
          text: isFilled ? Colors.white : AppColors.success,
          border: AppColors.success.withOpacity(0.3),
        );
      case StatusType.warning:
        return _BadgeColors(
          background: AppColors.warning,
          text: isFilled ? Colors.white : AppColors.warning,
          border: AppColors.warning.withOpacity(0.3),
        );
      case StatusType.error:
        return _BadgeColors(
          background: AppColors.error,
          text: isFilled ? Colors.white : AppColors.error,
          border: AppColors.error.withOpacity(0.3),
        );
      case StatusType.pending:
        return _BadgeColors(
          background: AppColors.textTertiary,
          text: isFilled ? Colors.white : AppColors.textSecondary,
          border: AppColors.textTertiary.withOpacity(0.3),
        );
      case StatusType.info:
      default:
        return _BadgeColors(
          background: AppColors.info,
          text: isFilled ? Colors.white : AppColors.info,
          border: AppColors.info.withOpacity(0.3),
        );
    }
  }
}

class _BadgeColors {
  final Color background;
  final Color text;
  final Color border;

  _BadgeColors({
    required this.background,
    required this.text,
    required this.border,
  });
}

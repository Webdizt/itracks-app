import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../config/constants.dart';

enum CardVariant { elevated, filled, outlined, glass }

class ModernCard extends StatelessWidget {
  final Widget child;
  final CardVariant variant;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final List<BoxShadow>? shadows;
  final Border? border;
  final Gradient? gradient;

  const ModernCard({
    Key? key,
    required this.child,
    this.variant = CardVariant.elevated,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.backgroundColor,
    this.shadows,
    this.border,
    this.gradient,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding ?? EdgeInsets.all(12.w), // ✅ DEFAULT KECIL
      decoration: BoxDecoration(
        color: gradient != null ? null : _getBackgroundColor(),
        gradient: gradient,
        borderRadius: BorderRadius.circular((borderRadius ?? AppRadius.md).r),
        border: border ?? _getBorder(),
        boxShadow: shadows ?? _getShadows(),
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          margin: margin,
          child: content,
        ),
      );
    }
    return Container(margin: margin, child: content);
  }

  Color _getBackgroundColor() {
    if (backgroundColor != null) return backgroundColor!;
    switch (variant) {
      case CardVariant.elevated:
        return AppColors.surface;
      case CardVariant.filled:
        return AppColors.surfaceVariant;
      case CardVariant.outlined:
        return AppColors.surface;
      case CardVariant.glass:
        return AppColors.glassWhite;
    }
  }

  Border? _getBorder() {
    switch (variant) {
      case CardVariant.outlined:
        return Border.all(color: AppColors.border);
      case CardVariant.glass:
        return Border.all(color: Colors.white.withOpacity(0.2));
      default:
        return null;
    }
  }

  List<BoxShadow> _getShadows() {
    switch (variant) {
      case CardVariant.elevated:
        return [AppShadows.small];
      case CardVariant.filled:
        return [];
      case CardVariant.outlined:
        return [AppShadows.small];
      case CardVariant.glass:
        return [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)];
    }
  }
}

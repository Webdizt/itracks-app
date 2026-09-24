import 'dart:io';

class PlatformUtils {
  static bool get isIOS => Platform.isIOS;
  static bool get isAndroid => Platform.isAndroid;

  static String get platformName {
    if (isIOS) return 'iOS';
    if (isAndroid) return 'Android';
    return 'Unknown';
  }

  // iOS specific safe area handling
  static double get iosBottomSafeArea => isIOS ? 34.0 : 0.0;
  static double get iosTopSafeArea => isIOS ? 44.0 : 0.0;

  // Android specific back button handling
  static bool get hasPhysicalBackButton => isAndroid;
}

import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class AppPermissionHandler {
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      // Android 13+ uses new permissions
      final photos = await Permission.photos.request();
      return photos.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  static Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  static Future<bool> requestBluetoothPermission() async {
    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      return scan.isGranted && connect.isGranted;
    } else {
      final status = await Permission.bluetooth.request();
      return status.isGranted;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<Map<Permission, PermissionStatus>>
      requestAllPermissions() async {
    return await [
      Permission.camera,
      Permission.photos,
      Permission.location,
      Permission.bluetooth,
      Permission.notification,
    ].request();
  }
}

class PermissionHandler {
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status.isGranted;
  }
}

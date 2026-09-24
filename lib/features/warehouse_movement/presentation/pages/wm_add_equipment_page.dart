import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../inventory/domain/entities/qr_scan_result.dart';
import '../../data/datasources/warehouse_movement_remote_datasource.dart';

class WarehouseMovementAddEquipmentPage extends StatefulWidget {
  final String movementUuid;

  const WarehouseMovementAddEquipmentPage({
    super.key,
    required this.movementUuid,
  });

  @override
  State<WarehouseMovementAddEquipmentPage> createState() =>
      _WarehouseMovementAddEquipmentPageState();
}

class _WarehouseMovementAddEquipmentPageState
    extends State<WarehouseMovementAddEquipmentPage> {
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _selectedItem;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() => _loading = true);
    try {
      final token = await AppAuthSession.resolveApiBearerToken();
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.baseUrl,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Accept': 'application/json',
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );

      final response = await dio.get(
        '/api/inventory/list',
        queryParameters: {
          'page': 1,
          'limit': 30,
          'search': _searchController.text.trim(),
        },
      );
      final body = _responseMap(response.data);
      final rows = (body['data']?['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _selectedItem = rows.any((row) => '${row['id']}' == '${_selectedItem?['id']}')
            ? rows.firstWhere((row) => '${row['id']}' == '${_selectedItem?['id']}')
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load equipment: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _scanAsset() async {
    final rawCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const _WarehouseMovementAssetScannerPage(),
      ),
    );
    if (!mounted || rawCode == null || rawCode.trim().isEmpty) {
      return;
    }

    final qrResult = QrScanResult.fromRawData(rawCode);
    final assetCode = qrResult.assetCode.trim();
    final serialNumber = qrResult.sn.trim();
    final searchValue = assetCode.isNotEmpty
        ? assetCode
        : serialNumber.isNotEmpty
            ? serialNumber
            : rawCode.trim();

    _searchController.text = searchValue;
    await _loadInventory();
    if (!mounted) return;

    final normalizedAsset = _scanToken(assetCode);
    final normalizedSn = _scanToken(serialNumber);
    Map<String, dynamic>? matched;
    for (final item in _items) {
      final itemAsset = _scanToken('${item['asset_code'] ?? ''}');
      final itemSn = _scanToken(_displaySerial(item));
      if ((normalizedAsset.isNotEmpty && itemAsset == normalizedAsset) ||
          (normalizedSn.isNotEmpty && itemSn == normalizedSn)) {
        matched = item;
        break;
      }
    }

    if (matched != null) {
      setState(() => _selectedItem = matched);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Asset scan matched and selected.'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Scan result loaded into search: $searchValue'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Map<String, dynamic> _responseMap(dynamic rawData) {
    if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    }
    if (rawData is String) {
      final cleaned = rawData.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
      if (cleaned.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(cleaned);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    return <String, dynamic>{};
  }

  String _displayName(Map<String, dynamic> item) {
    for (final key in const [
      'inventory_model',
      'equipment_name',
      'inventory_group',
      'inventory_manufacture',
      'model',
      'group',
      'brand',
      'asset_name',
      'asset_code',
    ]) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != '-') {
        return value;
      }
    }
    return 'Inventory Item';
  }

  String _displaySerial(Map<String, dynamic> item) {
    for (final key in const ['sn', 'serial_number', 'equipment_sn']) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != '-') {
        return value;
      }
    }
    return '-';
  }

  String _resolveInventoryId(Map<String, dynamic> item) {
    for (final key in const [
      'inventory_id',
      'inventoryId',
      'raw_inventory_id',
      'item_id',
      'equipment_list',
    ]) {
      final value = '${item[key] ?? ''}'.trim();
      if (value.isNotEmpty && value != '-' && int.tryParse(value) != null) {
        return value;
      }
    }
    return '';
  }

  String _scanToken(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  Future<void> _save() async {
    if (_selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an equipment item first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final inventoryId = _resolveInventoryId(_selectedItem!);
    final assetCode = '${_selectedItem!['asset_code'] ?? ''}'.trim();
    final serialNumber = _displaySerial(_selectedItem!);
    try {
      final response = await sl<WarehouseMovementRemoteDataSource>().addMovementItem(
        uuid: widget.movementUuid,
        payload: {
          'item_type': 'equipment',
          if (inventoryId.isNotEmpty) 'inventory_id': inventoryId,
          'asset_code': assetCode,
          'serial_number': serialNumber,
          'qty': _qtyController.text.trim().isEmpty ? '1' : _qtyController.text.trim(),
          'remarks': _notesController.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${response['message'] ?? 'Equipment added successfully.'}'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final selectedKeys = _selectedItem!.keys.toList()..sort();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add equipment: $e\n'
            'inventory_id=$inventoryId\n'
            'asset_code=$assetCode\n'
            'sn=$serialNumber\n'
            'keys=${selectedKeys.join(', ')}',
          ),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Add Equipment'),
        actions: [
          IconButton(
            tooltip: 'Scan asset',
            onPressed: _scanAsset,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            onPressed: _loadInventory,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 10.h),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _loadInventory(),
              decoration: InputDecoration(
                hintText: 'Search asset code, model, serial number',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: _loadInventory,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Text(
                          'No equipment found.',
                          style: TextStyle(
                            fontSize: 14.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final selected = '${_selectedItem?['id']}' == '${item['id']}';
                          return InkWell(
                            borderRadius: BorderRadius.circular(18.r),
                            onTap: () => setState(() => _selectedItem = item),
                            child: Container(
                              padding: EdgeInsets.all(14.w),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18.r),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: selected ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Radio<String>(
                                    value: '${item['id']}',
                                    groupValue: '${_selectedItem?['id']}',
                                    onChanged: (_) => setState(() => _selectedItem = item),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _displayName(item),
                                          style: TextStyle(
                                            fontSize: 16.sp,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 6.h),
                                        Text(
                                          'Asset: ${item['asset_code'] ?? '-'}',
                                          style: TextStyle(
                                            fontSize: 13.sp,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          'SN: ${_displaySerial(item)}',
                                          style: TextStyle(
                                            fontSize: 13.sp,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          'Group: ${item['inventory_group'] ?? item['group'] ?? '-'}',
                                          style: TextStyle(
                                            fontSize: 13.sp,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            minimum: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                SizedBox(height: 12.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    label: Text(_saving ? 'Saving...' : 'Add to Movement'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseMovementAssetScannerPage extends StatefulWidget {
  const _WarehouseMovementAssetScannerPage();

  @override
  State<_WarehouseMovementAssetScannerPage> createState() =>
      _WarehouseMovementAssetScannerPageState();
}

class _WarehouseMovementAssetScannerPageState
    extends State<_WarehouseMovementAssetScannerPage>
    with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _loading = true;
  bool _permissionGranted = false;
  bool _handled = false;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_permissionGranted || _controller == null || _handled) return;
    if (state == AppLifecycleState.resumed) {
      _controller!.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _controller!.stop();
    }
  }

  Future<void> _checkPermission() async {
    if (Platform.isMacOS) {
      _initScanner();
      return;
    }

    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (!mounted) return;
    if (status.isGranted) {
      _initScanner();
    } else {
      setState(() {
        _permissionGranted = false;
        _loading = false;
      });
    }
  }

  void _initScanner() {
    if (!mounted) return;
    setState(() {
      _permissionGranted = true;
      _controller = MobileScannerController(
        facing: CameraFacing.back,
        torchEnabled: false,
        formats: const [
          BarcodeFormat.qrCode,
          BarcodeFormat.code128,
          BarcodeFormat.ean13,
          BarcodeFormat.code39,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
          BarcodeFormat.pdf417,
          BarcodeFormat.aztec,
        ],
      );
      _loading = false;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      _handled = true;
      _controller?.stop();
      Navigator.pop(context, raw);
      break;
    }
  }

  Future<void> _toggleFlash() async {
    await _controller?.toggleTorch();
    if (!mounted) return;
    setState(() => _flashOn = !_flashOn);
  }

  Future<void> _manualInput() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual Asset Code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Asset code or QR content',
          ),
          minLines: 1,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || value == null || value.trim().isEmpty) return;
    Navigator.pop(context, value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : !_permissionGranted
              ? _permissionView()
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_controller != null)
                      MobileScanner(
                        controller: _controller!,
                        onDetect: _onDetect,
                      ),
                    Center(
                      child: Container(
                        width: 250.w,
                        height: 250.w,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2.w,
                          ),
                          borderRadius: BorderRadius.circular(20.r),
                        ),
                      ),
                    ),
                    _header(),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 34.h,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _scanAction(
                            icon: _flashOn ? Icons.flash_on : Icons.flash_off,
                            onTap: _toggleFlash,
                          ),
                          SizedBox(width: 20.w),
                          _scanAction(
                            icon: Icons.keyboard_rounded,
                            onTap: _manualInput,
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 24.w,
                      right: 24.w,
                      bottom: 112.h,
                      child: Text(
                        'Scan QR asset atau barcode equipment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 14.sp,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _permissionView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 56.r),
            SizedBox(height: 16.h),
            Text(
              'Camera permission required',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              'Aktifkan kamera untuk scan asset.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13.sp),
            ),
            SizedBox(height: 18.h),
            OutlinedButton(
              onPressed: openAppSettings,
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12.h,
          bottom: 12.h,
          left: 8.w,
          right: 8.w,
        ),
        color: Colors.black.withOpacity(0.35),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
            Expanded(
              child: Text(
                'Scan Asset',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(width: 48.w),
          ],
        ),
      ),
    );
  }

  Widget _scanAction({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18.r),
      onTap: onTap,
      child: Container(
        width: 54.w,
        height: 54.w,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 26.r),
      ),
    );
  }
}

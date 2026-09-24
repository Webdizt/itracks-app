import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../../inventory/domain/entities/inventory_detail.dart';
import '../../../inventory/domain/entities/qr_scan_result.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';
import '../../../dn/presentation/pages/dn_page.dart';

enum ScanTarget { asset, deliveryNote }

class ScanPage extends StatefulWidget {
  final ScanTarget initialTarget;

  /// The scanner lives inside an IndexedStack. It must release the camera
  /// whenever another bottom-navigation page is visible.
  final bool isActive;

  const ScanPage(
      {Key? key, this.initialTarget = ScanTarget.asset, this.isActive = true})
      : super(key: key);

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  MobileScannerController? controller;
  bool isPermissionGranted = false;
  bool isLoading = true;
  bool isFlashOn = false;
  bool isBackCamera = true;
  bool isScanning = true;
  bool isProcessingScan = false;
  bool _cameraOperationInProgress = false;
  bool _appInForeground = true;
  String? lastScan;
  InventoryDetail? scannedDetail;
  QrScanResult? scannedQrResult;
  late ScanTarget scanTarget;

  @override
  void initState() {
    super.initState();
    scanTarget = widget.initialTarget;
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void didUpdateWidget(covariant ScanPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;

    if (!widget.isActive) {
      // Do not retain the CameraX session while this tab is hidden. A second
      // scanner (for example the DN QR scanner) can then start reliably.
      _stopScannerSafely();
      return;
    }

    if (controller == null) {
      _initScanner();
    } else if (!isProcessingScan) {
      _startScannerSafely();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopScannerSafely();
    controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        if (isPermissionGranted && widget.isActive && !isProcessingScan) {
          if (controller == null) {
            _initScanner();
          } else {
            _startScannerSafely();
          }
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _appInForeground = false;
        _stopScannerSafely();
        break;
      default:
        break;
    }
  }

  Future<void> _checkPermission() async {
    if (Platform.isMacOS) {
      setState(() {
        isPermissionGranted = true;
        isLoading = widget.isActive;
      });
      if (widget.isActive) _initScanner();
      return;
    }

    final status = await Permission.camera.status;

    if (status.isGranted) {
      setState(() {
        isPermissionGranted = true;
        isLoading = widget.isActive;
      });
      if (widget.isActive) _initScanner();
    } else {
      setState(() {
        isPermissionGranted = false;
        isLoading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      isLoading = true;
    });

    final status = await Permission.camera.request();

    if (status.isGranted) {
      setState(() {
        isPermissionGranted = true;
      });
      if (widget.isActive) _initScanner();
    } else {
      setState(() {
        isPermissionGranted = false;
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to scan codes.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _initScanner() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted ||
          !widget.isActive ||
          !_appInForeground ||
          controller != null) {
        return;
      }

      setState(() {
        controller = MobileScannerController(
          facing: CameraFacing.back,
          torchEnabled: false,
          formats: [
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
        isLoading = false;
      });
    });
  }

  Future<void> _startScannerSafely() async {
    final scanner = controller;
    if (!mounted ||
        !widget.isActive ||
        !_appInForeground ||
        scanner == null ||
        _cameraOperationInProgress) {
      return;
    }
    _cameraOperationInProgress = true;
    try {
      await scanner.start();
    } on MobileScannerException {
      if (mounted && widget.isActive) await _recreateScanner();
    } finally {
      _cameraOperationInProgress = false;
      if (!_shouldRunCamera) _stopScannerSafely();
    }
  }

  Future<void> _stopScannerSafely() async {
    final scanner = controller;
    if (scanner == null || _cameraOperationInProgress) return;
    _cameraOperationInProgress = true;
    try {
      await scanner.stop();
    } catch (_) {
      // Kamera mungkin sudah berhenti ketika lifecycle Android berubah.
    } finally {
      _cameraOperationInProgress = false;
      if (_shouldRunCamera) _startScannerSafely();
    }
  }

  bool get _shouldRunCamera =>
      mounted && widget.isActive && _appInForeground && !isProcessingScan;

  Future<void> _recreateScanner() async {
    final oldController = controller;
    try {
      await oldController?.stop();
    } catch (_) {}
    oldController?.dispose();
    if (!mounted) return;
    if (!widget.isActive || !_appInForeground) {
      setState(() => controller = null);
      return;
    }
    setState(() {
      controller = MobileScannerController(
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
      isFlashOn = false;
      isBackCamera = true;
      isScanning = true;
      isProcessingScan = false;
      lastScan = null;
    });
  }

  Future<void> _toggleFlash() async {
    await controller?.toggleTorch();
    setState(() {
      isFlashOn = !isFlashOn;
    });
  }

  Future<void> _switchCamera() async {
    await controller?.switchCamera();
    setState(() {
      isBackCamera = !isBackCamera;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      );
    }

    if (!isPermissionGranted) {
      return _buildPermissionDenied();
    }

    return _buildScanner();
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.camera_alt_outlined,
              size: 64.r,
              color: Colors.white54,
            ),
            SizedBox(height: 20.h),
            Text(
              'Camera Permission Required',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'This app needs camera access to scan QR codes and barcodes.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14.sp,
              ),
            ),
            SizedBox(height: 32.h),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _requestPermission,
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  width: double.infinity,
                  height: 50.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(12.r),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'Allow Access',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            TextButton(
              onPressed: () async {
                await openAppSettings();
              },
              child: Text(
                'Open Settings',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller != null)
          MobileScanner(
            controller: controller!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt_outlined,
                        color: Colors.white70, size: 42),
                    const SizedBox(height: 12),
                    const Text(
                      'The camera is not available yet.',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _recreateScanner,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              );
            },
          )
        else
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        _buildOverlay(),
        _buildHeader(),
        if (scannedDetail == null) _buildScanTargetSelector(),
        if (scannedDetail == null) _buildControls(),
        if (scannedDetail == null) _buildInstructions(),
        if (scannedDetail != null) _buildResultSheet(scannedDetail!),
        if (isProcessingScan)
          Container(
            color: Colors.black.withOpacity(0.55),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (!isScanning || isProcessingScan) return;

    final barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null && barcode.rawValue != lastScan) {
        setState(() {
          lastScan = barcode.rawValue;
          isScanning = false;
          isProcessingScan = true;
        });

        _processDetectedCode(barcode.rawValue!);
        break;
      }
    }
  }

  Future<void> _processDetectedCode(String rawCode) async {
    await _stopScannerSafely();
    if (!mounted) return;
    await _handleScan(rawCode);
  }

  Future<void> _handleScan(String rawCode) async {
    if (scanTarget == ScanTarget.deliveryNote) {
      await _handleDnScan(rawCode);
      return;
    }

    final qrResult = QrScanResult.fromRawData(rawCode);
    final assetCode = qrResult.assetCode.trim();
    final serialNumber = qrResult.sn.trim();
    final hasSnLine = RegExp(
      r'^\s*SN\s*:',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(rawCode);

    if (assetCode.isEmpty) {
      _showErrorAndResume('The QR code does not contain a valid asset code.');
      return;
    }

    if (hasSnLine && serialNumber.isEmpty) {
      _showErrorAndResume('Serial number was not found in the QR code.');
      return;
    }

    final repository = sl<InventoryRepository>();
    InventoryDetail? detail;

    final byAsset = await repository.findInventoryByAssetCode(assetCode);
    if (!mounted) return;
    final assetLookupOk = await byAsset.fold<Future<bool>>(
      (failure) async {
        _showErrorAndResume(failure.message);
        return false;
      },
      (assetDetail) async {
        detail = assetDetail;
        return true;
      },
    );
    if (!assetLookupOk || !mounted) return;

    if (detail == null && serialNumber.isNotEmpty) {
      final bySn = await repository.findInventoryBySn(serialNumber);
      if (!mounted) return;
      final snLookupOk = await bySn.fold<Future<bool>>(
        (failure) async {
          _showErrorAndResume(failure.message);
          return false;
        },
        (snDetail) async {
          detail = snDetail;
          return true;
        },
      );
      if (!snLookupOk || !mounted) return;
    }

    if (detail == null) {
      _showErrorAndResume(
        serialNumber.isNotEmpty
            ? 'No asset was found for asset code $assetCode and serial number $serialNumber.'
            : 'No asset was found for asset code $assetCode.',
      );
      return;
    }

    final detailSn = (detail!.sn ?? '').trim();
    if (serialNumber.isNotEmpty &&
        detailSn.isNotEmpty &&
        _normalizeScanToken(detailSn) != _normalizeScanToken(serialNumber)) {
      final bySn = await repository.findInventoryBySn(serialNumber);
      if (!mounted) return;
      final resolvedBySn = await bySn.fold<Future<InventoryDetail?>>(
        (failure) async {
          _showErrorAndResume(failure.message);
          return null;
        },
        (snDetail) async => snDetail,
      );
      if (!mounted) return;
      if (resolvedBySn == null) {
        _showErrorAndResume('The serial number $serialNumber was not found.');
        return;
      }
      detail = resolvedBySn;
    }

    setState(() {
      scannedQrResult = qrResult;
      scannedDetail = detail;
      isProcessingScan = false;
    });
  }

  Future<void> _handleDnScan(String rawCode) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DnQrLookupPage(rawCode: rawCode),
      ),
    );
    if (!mounted) return;
    _resumeScanner(resetLastScan: true, clearResult: true);
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery Note updated.')),
      );
    }
  }

  String _normalizeScanToken(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  String _matchedAssetName(InventoryDetail detail) {
    final candidates = [
      detail.model,
      detail.brand,
      detail.categoryName,
      detail.group,
      detail.assetCode,
    ];
    for (final value in candidates) {
      final text = (value ?? '').trim();
      if (text.isNotEmpty && text != '-' && text != '0') {
        return text;
      }
    }
    return '-';
  }

  void _showErrorAndResume(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
    _resumeScanner(resetLastScan: true);
  }

  void _resumeScanner({bool resetLastScan = false, bool clearResult = true}) {
    if (!mounted) return;

    setState(() {
      isScanning = true;
      isProcessingScan = false;
      if (clearResult) {
        scannedDetail = null;
        scannedQrResult = null;
      }
      if (resetLastScan) {
        lastScan = null;
      }
    });
    Future<void>.delayed(
      const Duration(milliseconds: 350),
      _startScannerSafely,
    );
  }

  Widget _buildOverlay() {
    return Center(
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
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16.h,
          bottom: 16.h,
          left: 16.w,
          right: 16.w,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Text(
                'Scan Code',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 48.w),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Positioned(
      bottom: 32.h,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildControlButton(
            icon: isFlashOn ? Icons.flash_on : Icons.flash_off,
            onTap: _toggleFlash,
          ),
          SizedBox(width: 24.w),
          _buildControlButton(
            icon: Icons.flip_camera_ios,
            onTap: _switchCamera,
          ),
          SizedBox(width: 24.w),
          _buildControlButton(
            icon: Icons.keyboard,
            onTap: _showManualInput,
          ),
        ],
      ),
    );
  }

  Widget _buildScanTargetSelector() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 76.h,
      left: 36.w,
      right: 36.w,
      child: Container(
        padding: EdgeInsets.all(4.r),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.58),
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Row(
          children: [
            _buildTargetButton(
              target: ScanTarget.asset,
              icon: Icons.inventory_2_outlined,
              label: 'Asset',
            ),
            _buildTargetButton(
              target: ScanTarget.deliveryNote,
              icon: Icons.local_shipping_outlined,
              label: 'Delivery Note',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetButton({
    required ScanTarget target,
    required IconData icon,
    required String label,
  }) {
    final selected = scanTarget == target;
    return Expanded(
      child: InkWell(
        onTap: isProcessingScan
            ? null
            : () {
                setState(() {
                  scanTarget = target;
                  lastScan = null;
                });
              },
        borderRadius: BorderRadius.circular(11.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11.r),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17.r, color: Colors.white),
              SizedBox(width: 7.w),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Positioned(
      bottom: 120.h,
      left: 0,
      right: 0,
      child: Text(
        scanTarget == ScanTarget.deliveryNote
            ? 'Point the camera at the Delivery Note QR code.'
            : 'Point the camera at the asset QR code or barcode.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withOpacity(0.8),
          fontSize: 14.sp,
        ),
      ),
    );
  }

  Widget _buildResultSheet(InventoryDetail detail) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
          padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 20.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(100.r),
                ),
              ),
              SizedBox(height: 18.h),
              Container(
                width: 56.w,
                height: 56.w,
                decoration: const BoxDecoration(
                  color: Color(0xFF1EC98B),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 34.r,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Asset Found',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 14.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scanned QR Data',
                      style: TextStyle(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 14.h),
                    _buildBasicInfoRow(
                      'QR Asset Code',
                      scannedQrResult?.assetCode ?? '-',
                    ),
                    _buildBasicInfoRow(
                      'QR Asset Name',
                      scannedQrResult?.assetName ?? '-',
                    ),
                    _buildBasicInfoRow(
                      'QR Serial Number',
                      scannedQrResult?.sn ?? '-',
                    ),
                    _buildBasicInfoRow(
                      'Department',
                      scannedQrResult?.department ?? '-',
                    ),
                    _buildBasicInfoRow(
                      'Location',
                      scannedQrResult?.location ?? '-',
                    ),
                    _buildBasicInfoRow(
                      'Matched Item',
                      _matchedAssetName(detail),
                      isLast: true,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () =>
                      _resumeScanner(resetLastScan: true, clearResult: true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    'Scan Again',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoRow(
    String label,
    String? value, {
    bool isLast = false,
  }) {
    final displayValue = (value ?? '').trim().isEmpty ? '-' : value!.trim();

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
        iconSize: 28.r,
      ),
    );
  }

  void _showManualInput() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(scanTarget == ScanTarget.deliveryNote
            ? 'Input Delivery Note'
            : 'Input Asset'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Enter a QR or barcode value',
            prefixIcon: Icon(Icons.qr_code),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = textController.text.trim();
              if (value.isEmpty) return;

              Navigator.pop(dialogContext);
              setState(() {
                lastScan = value;
                isScanning = false;
                isProcessingScan = true;
              });
              controller?.stop();
              _handleScan(value);
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }
}

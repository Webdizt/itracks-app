import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../config/constants.dart';
import 'inventory_detail_page.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  String? _scannedData;
  int _scanCount = 0;

  @override
  Widget build(BuildContext context) {
    print('=== BUILD: scannedData=$_scannedData, count=$_scanCount ===');

    return Scaffold(
      backgroundColor: Colors.black,
      body: _scannedData == null ? _buildScanner() : _buildResult(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            print('=== ON DETECT ===');
            for (final barcode in capture.barcodes) {
              final rawValue = barcode.rawValue;
              print('Raw: $rawValue');

              if (rawValue != null && rawValue.isNotEmpty) {
                setState(() {
                  _scannedData = rawValue;
                  _scanCount++;
                });
                print('=== SET STATE DONE ===');
                break;
              }
            }
          },
        ),
        // Overlay
        Center(
          child: Container(
            width: 250.w,
            height: 250.w,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        // Back button
        SafeArea(
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    print('=== BUILD RESULT ===');

    // Parse asset code
    final lines = _scannedData!.trim().split('\n');
    String assetCode = '';
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.contains(':') && trimmed.isNotEmpty) {
        assetCode = trimmed;
        break;
      }
    }
    print('Asset: $assetCode');

    // Mock data sesuai screenshot
    final assetData = {
      'assetCode': assetCode.isNotEmpty ? assetCode : 'SSI-IT-1801-1024007',
      'brand': 'Asus',
      'model': 'Zenbook OLED 14 UX3405M',
      'serialNumber': 'S7N0CX105754319',
      'category': '20',
      'department': 'Management',
      'location': 'Jakarta Office',
      'status': 'Good',
    };

    return Scaffold(
      backgroundColor: const Color(0xFFE8EAF6), // Light purple background
      body: SafeArea(
        child: Column(
          children: [
            // Header dengan icon
            Container(
              width: double.infinity,
              color: const Color(0xFFE8EAF6),
              padding: EdgeInsets.only(top: 40.h, bottom: 60.h),
              child: Column(
                children: [
                  Container(
                    width: 80.w,
                    height: 80.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5C6BC0),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Icon(
                      Icons.inventory_2,
                      color: Colors.white,
                      size: 40.r,
                    ),
                  ),
                ],
              ),
            ),

            // Content Card - BISA SCROLL
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24.r),
                    topRight: Radius.circular(24.r),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title & Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              assetData['assetCode']!,
                              style: TextStyle(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 6.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(20.r),
                            ),
                            child: Text(
                              assetData['status']!,
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        '${assetData['brand']} • ${assetData['model']}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        'SN: ${assetData['serialNumber']}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      SizedBox(height: 24.h),

                      // Basic Information Section
                      Text(
                        'Basic Information',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      _buildInfoRow('Asset Code', assetData['assetCode']!),
                      _buildInfoRow('Brand', assetData['brand']!),
                      _buildInfoRow('Model', assetData['model']!),
                      _buildInfoRow(
                          'Serial Number', assetData['serialNumber']!),
                      _buildInfoRow('Category', assetData['category']!),
                      SizedBox(height: 24.h),

                      // Location & Usage Section
                      Text(
                        'Location & Usage',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      _buildInfoRow('Department', assetData['department']!),
                      _buildInfoRow('Location', assetData['location']!),
                      SizedBox(height: 32.h),

                      // Action Buttons
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () =>
                              _navigateToDetail(assetData['assetCode']!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5C6BC0),
                            padding: EdgeInsets.symmetric(vertical: 16.h),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: Text(
                            'GUNAKAN',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _scannedData = null;
                              _scanCount++;
                            });
                          },
                          child: Text(
                            'Scan Lagi',
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20.h),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToDetail(String assetCode) {
    print('=== NAVIGATE: $assetCode ===');

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => InventoryDetailPage(inventoryId: assetCode),
      ),
    )
        .then((_) {
      print('=== BACK FROM DETAIL ===');
      setState(() {
        _scannedData = null;
        _scanCount++;
      });
    });
  }
}

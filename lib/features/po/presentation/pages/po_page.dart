import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/constants.dart';

class POPage extends StatelessWidget {
  const POPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Purchase Order'),
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
      ),
      body: Center(
        child: Text('PO Page - Coming Soon', style: TextStyle(fontSize: 20.sp)),
      ),
    );
  }
}

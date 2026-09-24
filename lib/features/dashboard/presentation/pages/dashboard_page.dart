import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../config/constants.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../dn/presentation/pages/dn_page.dart';

/// Menggunakan endpoint dan session yang sama dengan dashboard DN web.
class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final cookie = await AppAuthSession.getStoredWebSessionCookie();
      final response = await Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
        headers: {
          'Accept': 'application/json',
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie
        },
      )).get('/api/dashboard');
      final body = _asMap(response.data);
      if (response.statusCode == 200 && body['data'] is Map) {
        if (mounted)
          setState(
              () => _data = Map<String, dynamic>.from(body['data'] as Map));
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception(
            'Your login session has expired. Please sign in again.');
      } else {
        throw Exception(_message(body) ?? 'Unable to load the dashboard.');
      }
    } on DioException {
      if (mounted)
        setState(() => _error =
            'Server DN belum dapat dijangkau. Periksa alamat server dan jaringan Wi-Fi.');
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      final value = jsonDecode(raw);
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  String? _message(Map<String, dynamic> body) {
    final value = '${body['message'] ?? body['error'] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  int _stat(String field) {
    final stats = _data['stats'];
    return stats is Map ? int.tryParse('${stats[field] ?? 0}') ?? 0 : 0;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F6F5),
        body: SafeArea(
            child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _errorView()
                  : _content(),
        )),
      );

  Widget _errorView() => ListView(padding: EdgeInsets.all(24.w), children: [
        SizedBox(height: 115.h),
        const Icon(Icons.cloud_off_outlined,
            size: 42, color: Color(0xFF5F5B58)),
        SizedBox(height: 14.h),
        Text('Data dashboard belum tersedia',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
        SizedBox(height: 8.h),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.sp, color: const Color(0xFF6B6662))),
        SizedBox(height: 16.h),
        Center(
            child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'))),
      ]);

  Widget _content() {
    final userName = '${_data['userName'] ?? 'Pengguna'}'.trim();
    final recent = _data['recent'] is List ? _data['recent'] as List : const [];
    final metrics = [
      _Metric('Total DAN', _stat('totalOutgoing'), Icons.description_outlined,
          const Color(0xFF201E1C)),
      _Metric('Persiapan', _stat('preparation'), Icons.schedule_outlined,
          const Color(0xFFB45309)),
      _Metric('Dalam kirim', _stat('inTransit'), Icons.local_shipping_outlined,
          const Color(0xFF0369A1)),
      _Metric('Diterima', _stat('receivedOutgoing'), Icons.check_circle_outline,
          const Color(0xFF047857)),
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 98.h),
      children: [
        _header(userName),
        SizedBox(height: 14.h),
        Text('Ringkasan pengiriman',
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
        SizedBox(height: 9.h),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 9.h,
            crossAxisSpacing: 9.w,
            mainAxisExtent: 92.h,
          ),
          itemBuilder: (_, index) => _metricCard(metrics[index]),
        ),
        SizedBox(height: 20.h),
        Row(children: [
          Expanded(
              child: Text('Delivery note terbaru',
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))),
          IconButton(
              onPressed: _load,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh, size: 20))
        ]),
        SizedBox(height: 4.h),
        if (recent.isEmpty)
          _emptyRecent()
        else
          ...recent
              .take(6)
              .whereType<Map>()
              .map((row) => _recentItem(Map<String, dynamic>.from(row))),
      ],
    );
  }

  Widget _header(String userName) => Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
            color: const Color(0xFF0B0A09),
            borderRadius: BorderRadius.circular(15.r)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('iTrack · Delivery Note',
              style: TextStyle(fontSize: 11.sp, color: Colors.white70)),
          SizedBox(height: 5.h),
          Text('Halo, $userName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          SizedBox(height: 10.h),
          SizedBox(
            height: 34.h,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DnCreatePage())),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Buat DAN'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54)),
            ),
          ),
        ]),
      );

  Widget _metricCard(_Metric item) => Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: const Color(0xFFE6E3E0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(item.icon, size: 19.r, color: item.color),
            const Spacer(),
            Text('${item.value}',
                style: TextStyle(
                    fontSize: 23.sp,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1917)))
          ]),
          const Spacer(),
          Text(item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _emptyRecent() => Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12.r)),
      child: Text('Belum ada delivery note terbaru.',
          style: TextStyle(fontSize: 13.sp, color: const Color(0xFF78716C))));

  Widget _recentItem(Map<String, dynamic> item) {
    final number = '${item['danNumber'] ?? item['uuid'] ?? '-'}';
    final destination =
        '${item['destination'] ?? item['jobNumber'] ?? 'Tanpa tujuan'}';
    final status = '${item['status'] ?? 'Diproses'}';
    return Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: const Color(0xFFEDEAE7))),
        child: Row(children: [
          Container(
              width: 34.w,
              height: 34.w,
              decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8.r)),
              child: const Icon(Icons.description_outlined, size: 18)),
          SizedBox(width: 10.w),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(number,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 2.h),
                Text(destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.sp, color: const Color(0xFF78716C)))
              ])),
          SizedBox(width: 8.w),
          Text(status,
              style:
                  TextStyle(fontSize: 10.sp, color: const Color(0xFF57534E))),
        ]));
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

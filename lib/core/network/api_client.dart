import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/constants.dart';
import '../auth/app_auth_session.dart';
import 'network_info.dart';

class ApiClient {
  final Dio dio;
  final NetworkInfo networkInfo;

  ApiClient({
    required this.networkInfo,
  }) : dio = Dio() {
    _initDio();
  }

  void _initDio() {
    dio.options.baseUrl = AppConstants.baseUrl;
    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);
    dio.options.responseType = ResponseType.plain;
    dio.options.validateStatus = (_) => true;
    dio.options.headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<Options> _authorizedOptions([Options? options]) async {
    final token = await AppAuthSession.resolveApiBearerToken();
    // DN web memakai express-session. Flutter tidak menyimpan cookie HTTP
    // otomatis, sehingga cookie sesi harus dikirim kembali pada setiap request.
    final sessionCookie = await AppAuthSession.getStoredWebSessionCookie();
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?options?.headers,
    };

    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (sessionCookie != null && sessionCookie.isNotEmpty) {
      headers['Cookie'] = sessionCookie;
    }

    return (options ?? Options()).copyWith(headers: headers);
  }

  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    final connected = await networkInfo.isConnected;
    debugPrint('[API][GET] path=$path connected=$connected');
    return await dio.get(
      path,
      queryParameters: queryParameters,
      options: await _authorizedOptions(),
    );
  }

  Future<Response> post(String path, {dynamic data}) async {
    final connected = await networkInfo.isConnected;
    debugPrint('[API][POST] path=$path connected=$connected');
    return await dio.post(
      path,
      data: data,
      options: await _authorizedOptions(),
    );
  }
}

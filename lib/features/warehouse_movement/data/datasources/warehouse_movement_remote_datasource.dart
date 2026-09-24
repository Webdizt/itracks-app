import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../config/constants.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/warehouse_movement_create_data_model.dart';
import '../models/warehouse_movement_detail_model.dart';
import '../models/warehouse_movement_model.dart';

abstract class WarehouseMovementRemoteDataSource {
  Future<WarehouseMovementCreateDataModel> getCreateData();

  Future<List<WarehouseMovementModel>> getMovementList({
    String? search,
    String? status,
    String? transactionType,
    int page = 1,
    int limit = 20,
  });

  Future<WarehouseMovementDetailModel> getMovementDetail(String uuid);

  Future<Map<String, dynamic>> addMovementItem({
    required String uuid,
    required Map<String, dynamic> payload,
  });

  Future<void> deleteMovementItem({
    required String uuid,
    required String itemId,
  });

  Future<Map<String, dynamic>> submitMovement({
    required String uuid,
  });
}

class WarehouseMovementRemoteDataSourceImpl
    implements WarehouseMovementRemoteDataSource {
  final ApiClient client;

  WarehouseMovementRemoteDataSourceImpl({required this.client});

  Map<String, dynamic> _responseMap(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String) {
      final cleaned = raw.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
      if (cleaned.isEmpty) {
        return <String, dynamic>{};
      }

      try {
        final decoded = jsonDecode(cleaned);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        final jsonStart = cleaned.indexOf('{');
        final jsonEnd = cleaned.lastIndexOf('}');
        if (jsonStart >= 0 && jsonEnd > jsonStart) {
          final candidate = cleaned.substring(jsonStart, jsonEnd + 1);
          try {
            final decoded = jsonDecode(candidate);
            if (decoded is Map) {
              return Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }
      }

      return <String, dynamic>{
        '_raw_text': cleaned,
      };
    }
    return <String, dynamic>{};
  }

  String _snippet(dynamic raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) {
      return '(empty)';
    }
    return text.length > 300 ? text.substring(0, 300) : text;
  }

  bool _isInvalidTokenResponse(Response response, Map<String, dynamic> body) {
    return response.statusCode == 401 &&
        '${body['message'] ?? ''}'.toLowerCase().contains('invalid token') &&
        AppConstants.apiStaticToken.trim().isNotEmpty;
  }

  bool _isUnauthorizedBody(Map<String, dynamic> body) {
    final message = '${body['message'] ?? ''}'.trim().toLowerCase();
    return message.contains('invalid token') ||
        message.contains('unauthorized') ||
        message.contains('access denied') ||
        message.contains('forbidden');
  }

  List<dynamic> _listRows(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is List) return data;
    if (data is Map) {
      for (final key in const ['items', 'rows', 'records', 'data', 'list']) {
        final value = data[key];
        if (value is List) return value;
      }
    }
    for (final key in const ['items', 'rows', 'records', 'list']) {
      final value = body[key];
      if (value is List) return value;
    }
    return const [];
  }

  List<Map<String, dynamic>> _mapRows(List<dynamic> rows) {
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  bool _shouldRetryAuth(Response response, Map<String, dynamic> body) {
    return _isInvalidTokenResponse(response, body) ||
        response.statusCode == 401 ||
        response.statusCode == 403 ||
        (response.statusCode == 200 &&
            body['status'] == false &&
            _isUnauthorizedBody(body));
  }

  Future<Response> _getWithStaticToken(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final staticToken = AppConstants.apiStaticToken.trim();
    return client.dio.get(
      path,
      queryParameters: queryParameters,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (staticToken.isNotEmpty) ...{
            'Authorization': 'Bearer $staticToken',
            'X-API-Key': staticToken,
            'X-API-Token': staticToken,
            'X-Api-Secret': staticToken,
          },
        },
      ),
    );
  }

  Future<Response> _getWithSession(
    String path, {
    String? cookie,
    String? token,
    Map<String, dynamic>? queryParameters,
  }) {
    return client.dio.get(
      path,
      queryParameters: queryParameters,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  Future<Response> _safeGet(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final cookie = await AppAuthSession.getStoredWebSessionCookie();
    final token = await AppAuthSession.resolveApiBearerToken();
    Response response = await _getWithSession(
      path,
      cookie: cookie,
      token: token,
      queryParameters: queryParameters,
    );
    Map<String, dynamic> body = _responseMap(response.data);

    if (cookie != null && cookie.isNotEmpty && _shouldRetryAuth(response, body)) {
      debugPrint(
        '[WM][TOKEN_RETRY][GET] path=$path status=${response.statusCode} body=${_snippet(response.data)}',
      );
      response = await client.get(path, queryParameters: queryParameters);
      body = _responseMap(response.data);
    }

    if (path == '/api/warehouse-movement/create-data' &&
        AppConstants.apiStaticToken.trim().isNotEmpty &&
        _shouldRetryAuth(response, body)) {
      debugPrint(
        '[WM][STATIC_RETRY][GET] path=$path status=${response.statusCode} body=${_snippet(response.data)}',
      );
      response = await _getWithStaticToken(
        path,
        queryParameters: queryParameters,
      );
    }

    return response;
  }

  Future<Response> _safePost(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    final cookie = await AppAuthSession.getStoredWebSessionCookie();
    final token = await AppAuthSession.resolveApiBearerToken();
    Response response = await _postWithSession(
      path,
      cookie: cookie,
      token: token,
      data: data,
    );
    Map<String, dynamic> body = _responseMap(response.data);

    if (cookie != null && cookie.isNotEmpty && _shouldRetryAuth(response, body)) {
      debugPrint(
        '[WM][TOKEN_RETRY][POST] path=$path status=${response.statusCode} body=${_snippet(response.data)}',
      );
      response = await client.post(path, data: data);
      body = _responseMap(response.data);
    }

    if (path == '/api/warehouse-movement/create-data' &&
        AppConstants.apiStaticToken.trim().isNotEmpty &&
        _shouldRetryAuth(response, body)) {
      debugPrint(
        '[WM][STATIC_RETRY][POST] path=$path status=${response.statusCode} body=${_snippet(response.data)}',
      );
      response = await _postWithStaticToken(path, data: data);
    }

    return response;
  }

  Future<Response> _postWithStaticToken(
    String path, {
    Map<String, dynamic>? data,
  }) {
    final staticToken = AppConstants.apiStaticToken.trim();
    return client.dio.post(
      path,
      data: data,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (staticToken.isNotEmpty) ...{
            'Authorization': 'Bearer $staticToken',
            'X-API-Key': staticToken,
            'X-API-Token': staticToken,
            'X-Api-Secret': staticToken,
          },
        },
      ),
    );
  }

  Future<Response> _postWithSession(
    String path, {
    String? cookie,
    String? token,
    Map<String, dynamic>? data,
  }) {
    return client.dio.post(
      path,
      data: data,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
      ),
    );
  }

  @override
  Future<WarehouseMovementCreateDataModel> getCreateData() async {
    try {
      Response response = await _safeGet('/api/warehouse-movement/create-data');
      Map<String, dynamic> body = _responseMap(response.data);
      debugPrint(
        '[WM][CREATE_DATA][HTTP] status=${response.statusCode} body=${_snippet(response.data)}',
      );
      if (response.statusCode == 200 && body['status'] == true) {
        return WarehouseMovementCreateDataModel.fromJson(
          Map<String, dynamic>.from(body['data'] ?? const {}),
        );
      }
      throw ServerException(
        message: _resolveErrorMessage(
          body,
          fallback: 'Failed to load warehouse movement create data',
        ),
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<List<WarehouseMovementModel>> getMovementList({
    String? search,
    String? status,
    String? transactionType,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      Response response = await _safeGet(
        '/api/warehouse-movement/list',
        queryParameters: {
          if (search != null && search.trim().isNotEmpty) 'search': search,
          if (status != null && status.trim().isNotEmpty) 'status': status,
          if (transactionType != null && transactionType.trim().isNotEmpty)
            'transaction_type': transactionType,
          'page': page,
          'limit': limit,
        },
      );
      Map<String, dynamic> body = _responseMap(response.data);
      debugPrint(
        '[WM][LIST][HTTP] status=${response.statusCode} body=${_snippet(response.data)}',
      );
      if (response.statusCode == 200 && body['status'] == true) {
        final items = _mapRows(_listRows(body));
        return items
            .map((e) => WarehouseMovementModel.fromJson(e))
            .toList();
      }
      throw ServerException(
        message: _resolveErrorMessage(
          body,
          fallback: 'Failed to load warehouse movement list',
        ),
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<WarehouseMovementDetailModel> getMovementDetail(String uuid) async {
    try {
      Response response = await _safeGet(
        '/api/warehouse-movement/detail/${Uri.encodeComponent(uuid)}',
      );
      Map<String, dynamic> body = _responseMap(response.data);
      debugPrint(
        '[WM][DETAIL][HTTP] status=${response.statusCode} body=${_snippet(response.data)}',
      );
      if (response.statusCode == 200 && body['status'] == true) {
        return WarehouseMovementDetailModel.fromJson(
          Map<String, dynamic>.from(body['data'] ?? const {}),
        );
      }
      throw ServerException(
        message: _resolveErrorMessage(
          body,
          fallback: 'Failed to load warehouse movement detail',
        ),
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<Map<String, dynamic>> addMovementItem({
    required String uuid,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final requestData = {
        'uuid': uuid,
        ...payload,
      };
      Response response = await _safePost(
        '/api/warehouse-movement/item/add',
        data: requestData,
      );
      Map<String, dynamic> body = _responseMap(response.data);
      debugPrint(
        '[WM][ADD_ITEM][HTTP] status=${response.statusCode} body=${_snippet(response.data)}',
      );
      if (response.statusCode == 200 && body['status'] == true) {
        return body;
      }
      throw ServerException(
        message: _resolveErrorMessage(
          body,
          fallback: 'Failed to add warehouse movement item',
        ),
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<void> deleteMovementItem({
    required String uuid,
    required String itemId,
  }) async {
    try {
      final requestData = {
        'uuid': uuid,
        'item_id': itemId,
      };
      Response response = await _safePost(
        '/api/warehouse-movement/item/delete',
        data: requestData,
      );
      Map<String, dynamic> body = _responseMap(response.data);
      debugPrint(
        '[WM][DELETE_ITEM][HTTP] status=${response.statusCode} body=${_snippet(response.data)}',
      );
      if (response.statusCode == 200 && body['status'] == true) {
        return;
      }
      throw ServerException(
        message: _resolveErrorMessage(
          body,
          fallback: 'Failed to delete warehouse movement item',
        ),
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<Map<String, dynamic>> submitMovement({
    required String uuid,
  }) async {
    try {
      final requestData = {
        'uuid': uuid,
      };
      Response response = await _safePost(
        '/api/warehouse-movement/submit',
        data: requestData,
      );
      Map<String, dynamic> body = _responseMap(response.data);
      debugPrint(
        '[WM][SUBMIT][HTTP] status=${response.statusCode} body=${_snippet(response.data)}',
      );
      if (response.statusCode == 200 && body['status'] == true) {
        return body;
      }
      throw ServerException(
        message: _resolveErrorMessage(
          body,
          fallback: 'Failed to submit warehouse movement',
        ),
      );
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  String _resolveErrorMessage(
    Map<String, dynamic> body, {
    required String fallback,
  }) {
    final message = '${body['message'] ?? ''}'.trim();
    if (message.isNotEmpty) {
      if (message.toLowerCase().contains('invalid token')) {
        return 'The Warehouse Movement login session is no longer valid. Sign out and sign in again so the server cookie can be stored.';
      }
      return message;
    }

    final rawText = '${body['_raw_text'] ?? ''}'.trim();
    if (rawText.startsWith('<')) {
      return 'WM API returned an HTML/PHP error page. Please check the warehouse movement backend on the server.';
    }
    if (rawText.isNotEmpty) {
      return rawText.length > 220 ? rawText.substring(0, 220) : rawText;
    }

    return fallback;
  }
}

import 'dart:convert';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/inventory_model.dart';
import '../models/inventory_detail_model.dart';

abstract class InventoryRemoteDataSource {
  Future<List<InventoryModel>> getInventoryList({
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? category,
  });

  Future<InventoryDetailModel> getInventoryDetail(String id);
  Future<void> updateInventory(String id, Map<String, dynamic> data);
}

class InventoryRemoteDataSourceImpl implements InventoryRemoteDataSource {
  final ApiClient client;

  InventoryRemoteDataSourceImpl({required this.client});

  @override
  Future<List<InventoryModel>> getInventoryList({
    int page = 1,
    int limit = 20,
    String? search,
    String? status,
    String? category,
  }) async {
    try {
      final response =
          await client.get('/api/inventory/list', queryParameters: {
        'page': page,
        'limit': limit,
        if (search != null) 'search': search,
        if (status != null) 'status': status,
        if (category != null) 'category': category,
      });

      final body = _responseMap(response.data);
      if (response.statusCode == 200 && body['status'] == true) {
        final items = _inventoryRows(body);
        return items
            .whereType<Map>()
            .map((e) => InventoryModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } else {
        throw ServerException(
          message: '${body['message'] ?? 'Failed to load inventory'}',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  // ✅ IMPLEMENTASI BARU
  @override
  Future<InventoryDetailModel> getInventoryDetail(String id) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await client.get('/api/inventory/detail/$encodedId');

      final body = _responseMap(response.data);

      if (response.statusCode == 200 && body['status'] == true) {
        final data = body['data'];

        // ✅ FIX: Data langsung berisi item, bukan data['item']
        // Cek apakah data adalah Map langsung atau ada nested 'item'
        final itemData =
            data is Map<String, dynamic> && data.containsKey('item')
                ? data['item']
                : data;

        if (itemData == null || itemData is! Map) {
          throw ServerException(message: 'Invalid response structure');
        }

        return InventoryDetailModel.fromJson(
            Map<String, dynamic>.from(itemData));
      } else {
        throw ServerException(
          message: '${body['message'] ?? 'Failed to load inventory detail'}',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }

  @override
  Future<void> updateInventory(String id, Map<String, dynamic> data) async {
    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await client.post(
        '/api/inventory/update/$encodedId',
        data: data,
      );

      final body = _responseMap(response.data);
      if (response.statusCode == 200 && body['status'] == true) {
        return;
      } else {
        throw ServerException(
          message: '${body['message'] ?? 'Failed to update inventory'}',
        );
      }
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(message: 'Network error: ${e.toString()}');
    }
  }
}

Map<String, dynamic> _responseMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String) {
    final cleaned = raw.replaceFirst(RegExp(r'^\uFEFF'), '').trim();
    if (cleaned.isEmpty) return const {};
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final decoded = jsonDecode(cleaned.substring(start, end + 1));
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
      }
    }
  }
  return const {};
}

List<dynamic> _inventoryRows(Map<String, dynamic> body) {
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

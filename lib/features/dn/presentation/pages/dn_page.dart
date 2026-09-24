import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../config/constants.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../barcode/presentation/pages/scan_page.dart';
import '../../../inventory/domain/entities/qr_scan_result.dart';

bool _shouldUseDnFallback(Object error) {
  if (error is DioException) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 404 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503) {
      return true;
    }
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }
  return false;
}

String _dnErrorMessage(Object error, {String? fallback}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      final message = '${data['message']}'.trim();
      if (message.isNotEmpty) {
        if (error.response?.statusCode == 401) {
          return 'DN access denied: $message. Please log out and sign in again.';
        }
        return message;
      }
    }

    if (error.response?.statusCode == 401) {
      return 'DN access denied. Your session is no longer valid. Please log out and sign in again.';
    }
  }
  return fallback ?? error.toString();
}

const String _dnCreateDataCacheKey = 'dn_create_data_cache_v2';
String _dnBoxItemsCacheKey(String uuid) => 'dn_box_items_cache_${uuid.trim()}';

Future<void> _storeDnCreateDataCache(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_dnCreateDataCacheKey, jsonEncode(data));
}

Future<Map<String, dynamic>?> _readDnCreateDataCache() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_dnCreateDataCacheKey);
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return null;
  }
  return null;
}

Future<Map<String, dynamic>> _readDnBoxItemsCache(String uuid) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_dnBoxItemsCacheKey(uuid));
  if (raw == null || raw.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return {};
  }
  return {};
}

Future<void> _writeDnBoxItemsCache(
    String uuid, Map<String, dynamic> cache) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_dnBoxItemsCacheKey(uuid), jsonEncode(cache));
}

String _dnBoxNumberKey(dynamic boxNumber) => '${boxNumber ?? ''}'.trim();

String _dnItemMatchKey(Map<String, dynamic> item) {
  final equipmentList =
      '${item['equipment_list'] ?? item['inventory_id'] ?? ''}'.trim();
  if (equipmentList.isNotEmpty) return 'list:$equipmentList';
  final assetCode = '${item['asset_code'] ?? ''}'.trim().toUpperCase();
  if (assetCode.isNotEmpty && assetCode != '-') return 'asset:$assetCode';
  final serial = _equipmentDisplaySerial(item).trim().toUpperCase();
  if (serial.isNotEmpty && serial != '-') return 'sn:$serial';
  final id = '${item['id'] ?? ''}'.trim();
  if (id.isNotEmpty) return 'id:$id';
  return '';
}

Future<void> _rememberDnBoxItems(
    String uuid, dynamic boxNumber, List<Map<String, dynamic>> items) async {
  final boxKey = _dnBoxNumberKey(boxNumber);
  if (boxKey.isEmpty) return;
  final cache = await _readDnBoxItemsCache(uuid);
  cache[boxKey] = items.map(_normalizeDnItem).toList();
  await _writeDnBoxItemsCache(uuid, cache);
}

Future<void> _removeDnBoxItemFromCache(
    String uuid, dynamic boxNumber, dynamic itemId) async {
  final boxKey = _dnBoxNumberKey(boxNumber);
  if (boxKey.isEmpty) return;
  final cache = await _readDnBoxItemsCache(uuid);
  final rows = (cache[boxKey] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  rows.removeWhere((item) => '${item['id']}' == '$itemId');
  cache[boxKey] = rows;
  await _writeDnBoxItemsCache(uuid, cache);
}

Future<List<Map<String, dynamic>>> _mergeDnBoxesWithCache(
    String uuid, List<Map<String, dynamic>> boxes) async {
  final cache = await _readDnBoxItemsCache(uuid);
  if (cache.isEmpty) return boxes;

  return boxes.map((box) {
    final mergedBox = Map<String, dynamic>.from(box);
    final boxKey = _dnBoxNumberKey(box['box_number']);
    final cachedItems = (cache[boxKey] as List? ?? const [])
        .whereType<Map>()
        .map((e) => _normalizeDnItem(Map<String, dynamic>.from(e)))
        .toList();
    final serverItems = _normalizeDnItems(box['items'] as List? ?? const []);

    if (serverItems.isEmpty && cachedItems.isNotEmpty) {
      mergedBox['items'] = cachedItems;
      return mergedBox;
    }

    final cachedByKey = <String, Map<String, dynamic>>{};
    for (final item in cachedItems) {
      final key = _dnItemMatchKey(item);
      if (key.isNotEmpty) cachedByKey[key] = item;
    }

    final usedKeys = <String>{};
    final mergedItems = serverItems.map((item) {
      final key = _dnItemMatchKey(item);
      final cached = key.isNotEmpty ? cachedByKey[key] : null;
      if (cached == null) {
        return item;
      }
      usedKeys.add(key);
      return _normalizeDnItem({
        ...cached,
        ...item,
        'equipment_name': _equipmentDisplayName({
          ...cached,
          ...item,
        }),
        'equipment_sn': _equipmentDisplaySerial({
          ...cached,
          ...item,
        }),
      });
    }).toList();

    for (final entry in cachedByKey.entries) {
      if (!usedKeys.contains(entry.key)) {
        mergedItems.add(entry.value);
      }
    }

    mergedBox['items'] = mergedItems;
    return mergedBox;
  }).toList();
}

List<Map<String, dynamic>> _normalizeDnAddresses(List<dynamic> rows) {
  return rows.map((item) => Map<String, dynamic>.from(item as Map)).map((row) {
    final parts = [
      row['address1'],
      row['address2'],
      row['address3'],
      row['address4'],
      row['address5'],
    ].where((part) => '$part'.trim().isNotEmpty).join('\n');
    final rawAddress = '${row['address'] ?? ''}'.trim();
    return {
      ...row,
      'company_name': row['company_name'] ?? row['name'] ?? '',
      'telp': row['telp'] ?? row['telephone'] ?? '',
      'fax': row['fax'] ?? '',
      'address': rawAddress.isNotEmpty ? rawAddress : parts,
    };
  }).toList();
}

bool _looksLikeOpaqueId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^[a-f0-9]{24,64}$', caseSensitive: false).hasMatch(trimmed);
}

bool _addressFlagEnabled(dynamic raw) {
  final value = '${raw ?? ''}'.trim().toLowerCase();
  return value == '1' ||
      value == '2' ||
      value == 'true' ||
      value == 'yes' ||
      value == 'y';
}

List<Map<String, dynamic>> _senderAddressOptions(
    List<Map<String, dynamic>> addresses) {
  final senderRows =
      addresses.where((row) => _addressFlagEnabled(row['sender'])).toList();
  return senderRows.isNotEmpty ? senderRows : addresses;
}

List<Map<String, dynamic>> _receiverAddressOptions(
    List<Map<String, dynamic>> addresses) {
  final receiverRows =
      addresses.where((row) => _addressFlagEnabled(row['receiver'])).toList();
  return receiverRows.isNotEmpty ? receiverRows : addresses;
}

String _firstNonEmptyValue(Map<String, dynamic> source, List<String> keys,
    {String fallback = ''}) {
  for (final key in keys) {
    final value = '${source[key] ?? ''}'.trim();
    if (value.isNotEmpty && value != '-') {
      return value;
    }
  }
  return fallback;
}

String _addressTextFromRow(Map<String, dynamic>? row) {
  if (row == null) return '';
  return _firstNonEmptyValue(
    row,
    ['address', 'address1', 'address2', 'address3', 'address4', 'address5'],
  );
}

String _equipmentDisplayName(Map<String, dynamic> item) {
  return _firstNonEmptyValue(
    item,
    [
      'equipment_name',
      'inventory_model',
      'inventory_group',
      'equipment_list_name',
      'inventory_manufacture',
      'model',
      'group',
      'brand',
      'asset_name',
      'asset_code',
    ],
    fallback: '-',
  );
}

String _equipmentDisplaySerial(Map<String, dynamic> item) {
  return _firstNonEmptyValue(
    item,
    ['equipment_sn', 'serial_number', 'sn'],
    fallback: '-',
  );
}

Map<String, dynamic> _normalizeDnItem(Map<String, dynamic> item) {
  final normalized = Map<String, dynamic>.from(item);
  final displayName = _equipmentDisplayName(normalized);
  final displaySerial = _equipmentDisplaySerial(normalized);
  final hasInventoryReference =
      '${normalized['equipment_list'] ?? normalized['inventory_id'] ?? normalized['id'] ?? ''}'
          .trim()
          .isNotEmpty;

  normalized['equipment_name'] = displayName == '-' && hasInventoryReference
      ? 'Inventory Item'
      : displayName;
  normalized['equipment_sn'] = displaySerial;
  normalized['equipment_qty'] = _firstNonEmptyValue(
    normalized,
    ['equipment_qty', 'qty'],
    fallback: '1',
  );
  normalized['equipment_value'] = _firstNonEmptyValue(
    normalized,
    ['equipment_value', 'value'],
    fallback: '0',
  );
  return normalized;
}

List<Map<String, dynamic>> _normalizeDnItems(List<dynamic> rows) {
  return rows
      .map((item) => Map<String, dynamic>.from(item as Map))
      .map(_normalizeDnItem)
      .toList();
}

List<Map<String, dynamic>> _normalizeDnBoxes(List<dynamic> rows) {
  return rows.map((item) {
    final box = Map<String, dynamic>.from(item as Map);
    box['items'] = _normalizeDnItems(box['items'] as List? ?? const []);
    return box;
  }).toList();
}

/// Respons web baru mengirim box dan item sebagai dua daftar terpisah.
/// Halaman Flutter lama memakai items di dalam setiap box, jadi satukan di sini.
List<Map<String, dynamic>> _attachDnItemsToBoxes(
  List<dynamic> boxRows,
  List<dynamic> itemRows,
) {
  final itemsByBox = <String, List<Map<String, dynamic>>>{};
  for (final raw in itemRows.whereType<Map>()) {
    final item = Map<String, dynamic>.from(raw);
    final boxKey = _dnBoxNumberKey(item['boxNumber'] ?? item['box_number']);
    if (boxKey.isEmpty) continue;
    itemsByBox.putIfAbsent(boxKey, () => []).add({
      ...item,
      'box_number': item['boxNumber'] ?? item['box_number'],
      'equipment_list': item['inventoryId'] ?? item['equipment_list'],
      'asset_code': item['assetCode'] ?? item['asset_code'],
      'equipment_name': item['equipment_name'] ?? item['name'],
      'equipment_sn': item['equipment_sn'] ?? item['serialNumber'],
      'equipment_qty': item['equipment_qty'] ?? item['quantity'],
      'equipment_value': item['equipment_value'] ?? item['value'],
    });
  }
  return _normalizeDnBoxes(boxRows.map((raw) {
    final box = Map<String, dynamic>.from(raw as Map);
    final boxKey = _dnBoxNumberKey(box['box_number'] ?? box['boxNumber']);
    return {
      ...box,
      'box_number': box['box_number'] ?? box['boxNumber'],
      'items': itemsByBox[boxKey] ?? const [],
    };
  }).toList());
}

Future<int?> _findDnServerItemId(
  Dio dio, {
  required String uuid,
  required dynamic boxNumber,
  String? inventoryId,
  required String name,
  required String serial,
}) async {
  final response =
      await dio.get('/api/delivery-notes/${Uri.encodeComponent(uuid)}');
  final body = _dnResponseMap(response.data);
  final payload = body['data'];
  if (response.statusCode != 200 || payload is! Map) return null;
  final targetBox = _dnBoxNumberKey(boxNumber);
  final targetInventory = '${inventoryId ?? ''}'.trim();
  final targetName = name.trim().toLowerCase();
  final targetSerial = serial.trim().toLowerCase();
  final rows = (payload['items'] as List? ?? const [])
      .whereType<Map>()
      .toList()
      .reversed;
  for (final raw in rows) {
    final item = Map<String, dynamic>.from(raw);
    if (_dnBoxNumberKey(item['boxNumber'] ?? item['box_number']) != targetBox)
      continue;
    final itemInventory =
        '${item['inventoryId'] ?? item['equipment_list'] ?? ''}'.trim();
    final sameInventory =
        targetInventory.isNotEmpty && itemInventory == targetInventory;
    final itemName =
        '${item['name'] ?? item['equipment_name'] ?? ''}'.trim().toLowerCase();
    final itemSerial = '${item['serialNumber'] ?? item['equipment_sn'] ?? ''}'
        .trim()
        .toLowerCase();
    if (!sameInventory &&
        (itemName != targetName || itemSerial != targetSerial)) continue;
    return int.tryParse('${item['id'] ?? ''}');
  }
  return null;
}

Future<void> _uploadDnItemPhotos(
  Dio dio, {
  required String uuid,
  required int itemId,
  required List<XFile> photos,
}) async {
  for (final photo in photos) {
    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw Exception('Each photo must be 2 MB or smaller.');
    }
    final extension = photo.path.split('.').last.toLowerCase();
    final mimeType = extension == 'png'
        ? 'image/png'
        : extension == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final response = await dio.post(
      '/api/delivery-notes/${Uri.encodeComponent(uuid)}/items/$itemId/photos',
      data: {'photo': 'data:$mimeType;base64,${base64Encode(bytes)}'},
    );
    if (response.statusCode != 201) {
      final body = _dnResponseMap(response.data);
      throw Exception(
          '${body['message'] ?? 'The photo could not be uploaded.'}');
    }
  }
}

Future<Map<String, List<int>>> _loadDnItemPhotoIds(Dio dio, String uuid) async {
  final response = await dio
      .get('/api/delivery-notes/${Uri.encodeComponent(uuid)}/item-photos');
  final body = _dnResponseMap(response.data);
  if (response.statusCode != 200) return const {};
  final result = <String, List<int>>{};
  for (final raw in (body['data'] as List? ?? const []).whereType<Map>()) {
    final row = Map<String, dynamic>.from(raw);
    final itemId = '${row['itemId'] ?? ''}'.trim();
    final photoId = int.tryParse('${row['id'] ?? ''}');
    if (itemId.isEmpty || photoId == null) continue;
    result.putIfAbsent(itemId, () => []).add(photoId);
  }
  return result;
}

List<Map<String, dynamic>> _attachDnPhotoIds(
  List<Map<String, dynamic>> boxes,
  Map<String, List<int>> photoIds,
) {
  return boxes
      .map((box) => {
            ...box,
            'items':
                (box['items'] as List? ?? const []).whereType<Map>().map((raw) {
              final item = Map<String, dynamic>.from(raw);
              final ids = photoIds['${item['id'] ?? ''}'] ?? const <int>[];
              return {...item, 'photo_ids': ids, 'photo_count': ids.length};
            }).toList(),
          })
      .toList();
}

Map<String, dynamic>? _dnAddressOptionFromCurrent(
  Map<String, dynamic> dn, {
  required bool sender,
}) {
  final id = sender
      ? _firstNonEmptyValue(dn, ['sender_seascape', 'sender_id'])
      : _firstNonEmptyValue(
          dn, ['delivery_seascape', 'receiver_id', 'delivery_id']);
  final companyName = sender
      ? _firstNonEmptyValue(
          dn,
          ['sender_company_name', 'sender_company', 'sender_name'],
        )
      : _firstNonEmptyValue(
          dn,
          [
            'delivery_company_name',
            'delivery_company',
            'receiver_name',
            'destination_company_name'
          ],
        );
  final address = sender
      ? _firstNonEmptyValue(dn, ['sender_address'])
      : _firstNonEmptyValue(dn, ['delivery_address', 'destination_address']);
  final telp = sender
      ? _firstNonEmptyValue(dn, ['sender_tel', 'sender_telp', 'telephone'])
      : _firstNonEmptyValue(dn, ['receiver_tel', 'receiver_telp', 'attn_telp']);
  final fax = sender
      ? _firstNonEmptyValue(dn, ['sender_fax', 'fax'])
      : _firstNonEmptyValue(dn, ['receiver_fax', 'fax']);

  if (_looksLikeOpaqueId(companyName)) {
    return null;
  }

  if (id.isEmpty && companyName.isEmpty && address.isEmpty) {
    return null;
  }

  return {
    'id':
        id.isNotEmpty ? id : (sender ? 'fallback-sender' : 'fallback-receiver'),
    'company_name': companyName.isNotEmpty ? companyName : '-',
    'address': address,
    'telp': telp,
    'fax': fax,
    'sender': sender ? '1' : '0',
    'receiver': sender ? '0' : '1',
  };
}

String _friendlyApiMessage(
  Object error, {
  String fallback = 'Terjadi kesalahan saat memuat data.',
}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      final message = '${data['message']}'.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }

    final code = error.response?.statusCode;
    if (code == 500) {
      return 'The server could not process the request. Please try again shortly.';
    }
    if (code == 401) {
      return 'Your session is not valid. Please log out and sign in again.';
    }
    if (code == 404) {
      return 'The API endpoint is not available on the active server yet.';
    }
  }

  return fallback;
}

Map<String, dynamic> _dnResponseMap(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return raw;
  }
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
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      final jsonStart = cleaned.indexOf('{');
      final jsonEnd = cleaned.lastIndexOf('}');
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        try {
          final decoded = jsonDecode(cleaned.substring(jsonStart, jsonEnd + 1));
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
      return <String, dynamic>{'_raw_text': cleaned};
    }
  }
  return <String, dynamic>{};
}

List<dynamic> _dnListRows(Map<String, dynamic> body) {
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

bool _dnUnauthorizedBody(Map<String, dynamic> body) {
  final message =
      '${body['message'] ?? body['error'] ?? ''}'.trim().toLowerCase();
  return message.contains('invalid token') ||
      message.contains('unauthorized') ||
      message.contains('access denied') ||
      message.contains('forbidden');
}

bool _dnShouldRetryWithStaticToken(
    Response response, Map<String, dynamic> body) {
  if (AppConstants.apiStaticToken.trim().isEmpty) return false;
  if (response.statusCode == 401 || response.statusCode == 403) return true;
  return body['status'] == false && _dnUnauthorizedBody(body);
}

Future<void> _setDnAuthHeaders(Dio dio,
    {bool preferStaticToken = false}) async {
  final staticToken = AppConstants.apiStaticToken.trim();
  final sessionToken =
      (await AppAuthSession.resolveApiBearerToken() ?? '').trim();
  final token = preferStaticToken && staticToken.isNotEmpty
      ? staticToken
      : (sessionToken.isNotEmpty ? sessionToken : staticToken);
  final webSessionCookie = await AppAuthSession.getStoredWebSessionCookie();
  dio.options.headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    if (webSessionCookie != null && webSessionCookie.isNotEmpty)
      'Cookie': webSessionCookie,
  };
}

String _dnQrImageUrl(String uuid, {String? explicitUrl}) {
  final direct = (explicitUrl ?? '').trim();
  if (direct.isNotEmpty && !direct.contains('/box-qrcode/')) {
    return direct;
  }

  final cleanUuid = uuid.trim();
  if (cleanUuid.isEmpty) {
    return '';
  }

  return '${AppConstants.baseUrl}/extends/app-assets/images/itracks/dan/$cleanUuid.png';
}

String _boxQrImageUrl(Map<String, dynamic> box) {
  final qrId = _firstNonEmptyValue(
    box,
    ['box_qrcode', 'uuid', 'qr_uuid'],
  );
  if (qrId.isEmpty) {
    return '';
  }
  return '${AppConstants.baseUrl}/extends/app-assets/images/itracks/box/$qrId.png';
}

class DnPage extends StatefulWidget {
  const DnPage({Key? key}) : super(key: key);

  @override
  State<DnPage> createState() => _DnPageState();
}

class _DnPageState extends State<DnPage> {
  final _searchController = TextEditingController();
  late final Dio _dio;
  bool _loading = true;
  String? _error;
  bool _apiUnavailable = false;
  List<DnListItem> _items = const [];
  String _sessionUserName = '';

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    _loadSessionUser();
    _load();
  }

  Future<void> _loadSessionUser() async {
    final user = await AppAuthSession.getStoredUserData();
    if (!mounted || user == null) return;
    final name =
        '${user['name'] ?? user['username'] ?? user['email'] ?? ''}'.trim();
    if (name.isNotEmpty) setState(() => _sessionUserName = name);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _setAuth() async {
    await _setDnAuthHeaders(_dio);
  }

  Future<void> _setCreateDataAuth() async {
    await _setDnAuthHeaders(_dio, preferStaticToken: true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _apiUnavailable = false;
    });
    try {
      await _setAuth();
      final response = await _dio.get('/api/delivery-notes', queryParameters: {
        'search': _searchController.text.trim(),
        'page': 1,
        'pageSize': 100,
      });
      final body = _dnResponseMap(response.data);
      if (response.statusCode != 200 || body['data'] is! List) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          message: _dnErrorMessage(
            DioException(
                requestOptions: response.requestOptions, response: response),
            fallback:
                '${body['message'] ?? body['_raw_text'] ?? 'Failed to load DN data.'}',
          ),
        );
      }
      final rows = body['data'] as List;
      setState(() {
        _items = rows
            .map((e) => DnListItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (_shouldUseDnFallback(e)) {
        setState(() {
          _error =
              'The DN API is not available or cannot be reached from the app yet.';
          _apiUnavailable = true;
          _items = const [];
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = _dnErrorMessage(e);
        _items = const [];
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DnCreatePage()),
    );
    if (created == true) _load();
  }

  Future<void> _openDetail(DnListItem item) async {
    final normalizedStatus = item.status.toLowerCase().trim();
    final openReviewFirst =
        normalizedStatus == 'sent' || normalizedStatus == 'received';
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => openReviewFirst
            ? DnReviewPage(
                uuid: item.uuid,
                dnTitle: item.danNumber,
                currentDn: {
                  'dan_number': item.danNumber,
                  'status_text': item.status,
                  'job_number_text': item.jobNumber,
                  'delivery_date': item.deliveryDate,
                },
                currentBoxes: const [],
                senderName: '',
                receiverName: '',
                deliveryDate: item.deliveryDate,
                useSample: false,
                readOnly: true,
              )
            : DnDetailPage(
                uuid: item.uuid,
                title: item.danNumber,
              ),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Delivery Note'),
        actions: [
          IconButton(
            tooltip: 'Scan QR Delivery Note',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ScanPage(
                    initialTarget: ScanTarget.deliveryNote,
                  ),
                ),
              );
              if (mounted) _load();
            },
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Incoming delivery notes',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DnIncomingPage()),
              );
              if (mounted) _load();
            },
            icon: const Icon(Icons.move_to_inbox_outlined),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
            child: Column(
              children: [
                if (_apiUnavailable)
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 10.h),
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      'The DN API is not available on the active server. No demo fallback is shown here.',
                      style:
                          TextStyle(fontSize: 12.sp, color: AppColors.warning),
                    ),
                  ),
                TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'Search DN, proforma, job number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        onPressed: _load,
                        icon: const Icon(Icons.arrow_forward)),
                  ),
                ),
                if (_sessionUserName.isNotEmpty) ...[
                  SizedBox(height: 7.h),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Active account: $_sessionUserName',
                      style: TextStyle(
                          fontSize: 11.sp, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _apiUnavailable
                    ? _ApiUnavailableState(message: _error!, onRetry: _load)
                    : _error != null
                        ? _ErrorState(message: _error!, onRetry: _load)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: _items.isEmpty
                                ? ListView(
                                    children: const [
                                      SizedBox(height: 180),
                                      Center(child: Text('No DN found yet')),
                                    ],
                                  )
                                : ListView.builder(
                                    padding: EdgeInsets.fromLTRB(
                                        16.w, 8.h, 16.w, 120.h),
                                    itemCount: _items.length,
                                    itemBuilder: (context, index) {
                                      final item = _items[index];
                                      return _DnCard(
                                          item: item,
                                          onTap: () => _openDetail(item));
                                    },
                                  ),
                          ),
          ),
        ],
      ),
      floatingActionButton: _DnFloatingFabPadding(
        child: FloatingActionButton.extended(
          heroTag: 'dn_create_fab',
          onPressed: _openCreate,
          icon: const Icon(Icons.add),
          label: const Text('Add DN'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
    );
  }
}

class _DnFloatingFabPadding extends StatelessWidget {
  final Widget child;

  const _DnFloatingFabPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: 110.h + bottomInset),
      child: child,
    );
  }
}

class DnQrLookupPage extends StatefulWidget {
  final String rawCode;

  const DnQrLookupPage({super.key, required this.rawCode});

  @override
  State<DnQrLookupPage> createState() => _DnQrLookupPageState();
}

class _DnQrLookupPageState extends State<DnQrLookupPage> {
  late final Dio _dio;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    _resolve();
  }

  Future<void> _resolve() async {
    final reference = _DnQrReference.parse(widget.rawCode);
    if (!reference.isValid) {
      setState(() => _error =
          'The QR code does not contain a valid Delivery Note reference.');
      return;
    }

    try {
      await _setDnAuthHeaders(_dio);
      final resolved = await _resolveUuid(reference);
      if (resolved == null || resolved.uuid.isEmpty) {
        throw Exception('Delivery Note ${reference.label} was not found.');
      }

      final encodedUuid = Uri.encodeComponent(resolved.uuid);
      final incomingResponse = await _dio.get('/api/incoming/$encodedUuid');
      final incomingBody = _dnResponseMap(incomingResponse.data);
      final incomingData = incomingBody['data'];

      if (incomingResponse.statusCode == 200 && incomingData is Map) {
        final data = Map<String, dynamic>.from(incomingData);
        final header = Map<String, dynamic>.from(
          data['header'] as Map? ?? const {},
        );
        final status = '${header['statusLabel'] ?? header['status'] ?? ''}'
            .trim()
            .toLowerCase();
        final title = _firstNonEmptyValue(
          header,
          ['dan_number', 'danNumber'],
          fallback: resolved.title,
        );
        if (!mounted) return;
        await Navigator.pushReplacement<bool, bool>(
          context,
          MaterialPageRoute(
            builder: (_) => DnReceivePage(
              uuid: resolved.uuid,
              title: title,
              readOnly: status == 'received',
            ),
          ),
        );
        return;
      }

      final detailResponse = await _dio.get(
        '/api/delivery-notes/$encodedUuid',
      );
      var detailBody = _dnResponseMap(detailResponse.data);
      var detailData = detailBody['data'];
      if (detailResponse.statusCode != 200 || detailData is! Map) {
        final legacyResponse = await _dio.get('/api/dn/detail/$encodedUuid');
        final legacyBody = _dnResponseMap(legacyResponse.data);
        final legacyData = legacyBody['data'];
        if (legacyResponse.statusCode == 200 && legacyData is Map) {
          detailBody = legacyBody;
          detailData = legacyData;
        }
      }
      if (detailData is! Map) {
        throw Exception(
          '${detailBody['message'] ?? incomingBody['message'] ?? 'Unable to open this Delivery Note.'}',
        );
      }
      final header = Map<String, dynamic>.from(
        detailData['header'] as Map? ?? detailData['dn'] as Map? ?? const {},
      );
      final title = _firstNonEmptyValue(
        header,
        ['dan_number', 'danNumber'],
        fallback: resolved.title,
      );
      if (!mounted) return;
      await Navigator.pushReplacement<bool, bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DnDetailPage(
            uuid: resolved.uuid,
            title: title,
            forceReadOnly: true,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _dnErrorMessage(
          error,
          fallback: error.toString().replaceFirst('Exception: ', ''),
        );
      });
    }
  }

  Future<_ResolvedDn?> _resolveUuid(_DnQrReference reference) async {
    if (reference.looksLikeUuid) {
      return _ResolvedDn(uuid: reference.identifier, title: reference.label);
    }

    final response = await _dio.get(
      '/api/delivery-notes',
      queryParameters: {
        'search': reference.identifier,
        'page': 1,
        'pageSize': 20,
      },
    );
    final body = _dnResponseMap(response.data);
    final rows = _dnListRows(body).whereType<Map>();
    final normalizedTarget = reference.identifier.trim().toUpperCase();
    Map<String, dynamic>? first;
    for (final row in rows) {
      final item = Map<String, dynamic>.from(row);
      first ??= item;
      final number = '${item['danNumber'] ?? item['dan_number'] ?? ''}'
          .trim()
          .toUpperCase();
      if (number == normalizedTarget) {
        first = item;
        break;
      }
    }
    if (first == null) return null;
    final uuid = '${first['uuid'] ?? first['id'] ?? ''}'.trim();
    if (uuid.isEmpty) return null;
    final title = _firstNonEmptyValue(
      first,
      ['danNumber', 'dan_number'],
      fallback: reference.label,
    );
    return _ResolvedDn(uuid: uuid, title: title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Scan Delivery Note')),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    SizedBox(height: 18.h),
                    const Text(
                        'Checking the Delivery Note and receipt access...'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.qr_code_2_rounded,
                      size: 56,
                      color: AppColors.error,
                    ),
                    SizedBox(height: 16.h),
                    Text(_error!, textAlign: TextAlign.center),
                    SizedBox(height: 20.h),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Scan Again'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ResolvedDn {
  final String uuid;
  final String title;

  const _ResolvedDn({required this.uuid, required this.title});
}

class _DnQrReference {
  final String identifier;
  final String label;

  const _DnQrReference({required this.identifier, required this.label});

  bool get isValid => identifier.trim().isNotEmpty;
  bool get looksLikeUuid =>
      RegExp(r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$',
              caseSensitive: false)
          .hasMatch(identifier) ||
      _looksLikeOpaqueId(identifier);

  factory _DnQrReference.parse(String rawCode) {
    final raw = rawCode.trim();
    if (raw.isEmpty) return const _DnQrReference(identifier: '', label: '');

    String identifier = '';
    String label = '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        identifier = _firstNonEmptyValue(
          map,
          [
            'uuid',
            'dn_uuid',
            'delivery_note_uuid',
            'id',
            'dan_number',
            'danNumber'
          ],
        );
        label = _firstNonEmptyValue(
          map,
          ['dan_number', 'danNumber', 'dn_number', 'uuid'],
          fallback: identifier,
        );
      }
    } catch (_) {}

    final uri = Uri.tryParse(raw);
    if (identifier.isEmpty && uri != null && uri.hasScheme) {
      for (final key in const ['uuid', 'dn_uuid', 'id', 'dan_number', 'dn']) {
        final value = (uri.queryParameters[key] ?? '').trim();
        if (value.isNotEmpty) {
          identifier = value;
          break;
        }
      }
      if (identifier.isEmpty && uri.pathSegments.isNotEmpty) {
        final segments = uri.pathSegments
            .map(Uri.decodeComponent)
            .where((segment) => segment.trim().isNotEmpty)
            .toList();
        // QR pada PDF web berbentuk:
        // /delivery-note/outgoing/{uuid}/detail
        // Segmen terakhir adalah nama halaman, bukan identitas DN.
        final detailIndex = segments.lastIndexWhere(
          (segment) => segment.toLowerCase() == 'detail',
        );
        if (detailIndex > 0) {
          identifier = segments[detailIndex - 1].trim();
        } else {
          identifier = segments.last.trim();
        }
      }
      label = identifier;
    }

    if (identifier.isEmpty) {
      for (final line in raw.split(RegExp(r'[\r\n]+'))) {
        final match = RegExp(
          r'^(?:UUID|DN|DAN|DN\s*(?:NO|NUMBER)|DAN\s*(?:NO|NUMBER))\s*[:=]\s*(.+)$',
          caseSensitive: false,
        ).firstMatch(line.trim());
        if (match != null) {
          identifier = (match.group(1) ?? '').trim();
          label = identifier;
          break;
        }
      }
    }

    identifier = identifier.isEmpty ? raw : identifier;
    label = label.isEmpty ? identifier : label;
    return _DnQrReference(identifier: identifier, label: label);
  }
}

/// Mengambil identitas DN dari nilai mentah QR. Diekspos agar format QR dari
/// PDF web dapat diuji tanpa membuka kamera.
String dnIdentifierFromQr(String rawCode) =>
    _DnQrReference.parse(rawCode).identifier;

/// Delivery notes that may be received by the signed-in user. The server
/// authorizes administrators, internal share recipients, and the DN creator/
/// dispatcher; the client intentionally does not make an access decision.
class DnIncomingPage extends StatefulWidget {
  const DnIncomingPage({super.key});

  @override
  State<DnIncomingPage> createState() => _DnIncomingPageState();
}

class _DnIncomingPageState extends State<DnIncomingPage> {
  late final Dio _dio;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl, responseType: ResponseType.plain));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _setDnAuthHeaders(_dio);
      final response = await _dio.get('/api/incoming');
      final body = _dnResponseMap(response.data);
      if (response.statusCode != 200 || body['data'] is! List) {
        throw DioException(
            requestOptions: response.requestOptions, response: response);
      }
      if (!mounted) return;
      setState(() {
        _rows = (body['data'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _dnErrorMessage(error,
            fallback: 'Unable to load incoming delivery notes.');
        _loading = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DnReceivePage(
            uuid: '${row['uuid'] ?? ''}',
            title: '${row['danNumber'] ?? 'Delivery Note'}',
            readOnly: '${row['status'] ?? ''}'.toLowerCase() == 'received',
          ),
        ));
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.lightBackground,
        appBar: AppBar(title: const Text('Incoming Delivery Notes'), actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _rows.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 180),
                            Center(child: Text('No incoming delivery notes.'))
                          ])
                        : ListView.separated(
                            padding: EdgeInsets.all(16.w),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => SizedBox(height: 10.h),
                            itemBuilder: (_, index) {
                              final row = _rows[index];
                              final status = '${row['status'] ?? ''}';
                              final received =
                                  status.toLowerCase() == 'received';
                              return Card(
                                child: ListTile(
                                  leading: Icon(
                                      received
                                          ? Icons.task_alt
                                          : Icons.move_to_inbox_outlined,
                                      color: received
                                          ? Colors.teal
                                          : AppColors.primary),
                                  title: Text('${row['danNumber'] ?? '-'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                      'Job: ${row['jobNumber'] ?? '-'}\nTo: ${row['destination'] ?? '-'}\nSent by: ${row['dispatchedBy'] ?? '-'}'),
                                  isThreeLine: true,
                                  trailing: Chip(
                                      label:
                                          Text(status.isEmpty ? '-' : status)),
                                  onTap: () => _open(row),
                                ),
                              );
                            },
                          ),
                  ),
      );
}

class DnReceivePage extends StatefulWidget {
  final String uuid;
  final String title;
  final bool readOnly;
  const DnReceivePage(
      {super.key,
      required this.uuid,
      required this.title,
      required this.readOnly});

  @override
  State<DnReceivePage> createState() => _DnReceivePageState();
}

class _ReceiptItemState {
  _ReceiptItemState(this.item);
  final Map<String, dynamic> item;
  bool? conditionGood;
  final notes = TextEditingController();
  final List<XFile> photos = [];
  void dispose() => notes.dispose();
}

class _DnReceivePageState extends State<DnReceivePage> {
  late final Dio _dio;
  final _picker = ImagePicker();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _header;
  List<Map<String, dynamic>> _boxes = const [];
  final List<_ReceiptItemState> _items = [];
  DateTime _receivedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl, responseType: ResponseType.plain));
    _load();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _setDnAuthHeaders(_dio);
      final response = await _dio.get('/api/incoming/${widget.uuid}');
      final body = _dnResponseMap(response.data);
      final data = body['data'];
      if (response.statusCode != 200 || data is! Map)
        throw DioException(
            requestOptions: response.requestOptions, response: response);
      for (final item in _items) {
        item.dispose();
      }
      _items.clear();
      final map = Map<String, dynamic>.from(data);
      final loadedItems = (map['items'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row));
      for (final item in loadedItems) {
        final state = _ReceiptItemState(item);
        final value = item['conditionGood'];
        if (value is bool) state.conditionGood = value;
        if (value is num) state.conditionGood = value != 0;
        state.notes.text = '${item['incomingNotes'] ?? ''}';
        _items.add(state);
      }
      if (!mounted) return;
      setState(() {
        _header = Map<String, dynamic>.from(map['header'] as Map? ?? const {});
        _boxes = (map['boxes'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _dnErrorMessage(error,
            fallback: 'Unable to load the receipt details.');
        _loading = false;
      });
    }
  }

  Future<void> _addPhoto(_ReceiptItemState item) async {
    final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
                child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera)),
              ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from gallery'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery)),
            ])));
    if (source == null) return;
    final file = await _picker.pickImage(
        source: source, imageQuality: 72, maxWidth: 1600, maxHeight: 1600);
    if (file != null && mounted) setState(() => item.photos.add(file));
  }

  Future<String> _asDataUrl(XFile file) async {
    final bytes = await file.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }

  Map<String, String> get _imageHeaders => _dio.options.headers.map(
        (key, value) => MapEntry('$key', '$value'),
      );

  Future<void> _submit() async {
    if (_items.isEmpty || _items.any((item) => item.conditionGood == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Select Good or Not Good for every item.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final payloadItems = <Map<String, dynamic>>[];
      for (final item in _items) {
        payloadItems.add({
          'id': item.item['id'],
          'conditionGood': item.conditionGood,
          'notes': item.notes.text.trim(),
          'photos': await Future.wait(item.photos.map(_asDataUrl)),
        });
      }
      await _setDnAuthHeaders(_dio);
      final response =
          await _dio.post('/api/incoming/${widget.uuid}/receive', data: {
        'receivedDate':
            '${_receivedDate.year.toString().padLeft(4, '0')}-${_receivedDate.month.toString().padLeft(2, '0')}-${_receivedDate.day.toString().padLeft(2, '0')}',
        'items': payloadItems,
      });
      if (response.statusCode != 200)
        throw DioException(
            requestOptions: response.requestOptions, response: response);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Delivery Note received successfully.')));
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_dnErrorMessage(error,
                fallback: 'Unable to receive this Delivery Note.'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = '${_header?['statusLabel'] ?? ''}';
    final readOnly = widget.readOnly || status.toLowerCase() == 'received';
    final grouped = <String, List<_ReceiptItemState>>{};
    for (final item in _items) {
      grouped
          .putIfAbsent('${item.item['boxNumber'] ?? '-'}', () => [])
          .add(item);
    }
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
          title: Text(readOnly ? 'Receipt Details' : 'Receive Delivery Note')),
      bottomNavigationBar: readOnly
          ? null
          : SafeArea(
              child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
              child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.task_alt),
                  label: Text(_saving ? 'Saving...' : 'Confirm Receipt')),
            )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      16.w, 16.h, 16.w, readOnly ? 20.h : 90.h),
                  children: [
                    Card(
                        child: Padding(
                            padding: EdgeInsets.all(14.w),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '${_header?['dan_number'] ?? widget.title}',
                                      style: TextStyle(
                                          fontSize: 18.sp,
                                          fontWeight: FontWeight.w700)),
                                  SizedBox(height: 6.h),
                                  Text(
                                      'Job: ${_header?['jobNumberLabel'] ?? '-'}'),
                                  Text(
                                      'Dispatched by: ${_header?['dispatchedByName'] ?? '-'}'),
                                  if (!readOnly)
                                    Row(children: [
                                      const Text('Received date: '),
                                      TextButton(
                                          onPressed: () async {
                                            final chosen = await showDatePicker(
                                                context: context,
                                                initialDate: _receivedDate,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2100));
                                            if (chosen != null)
                                              setState(
                                                  () => _receivedDate = chosen);
                                          },
                                          child: Text(
                                              '${_receivedDate.day.toString().padLeft(2, '0')}/${_receivedDate.month.toString().padLeft(2, '0')}/${_receivedDate.year}'))
                                    ]),
                                ]))),
                    for (final entry in grouped.entries) ...[
                      SizedBox(height: 12.h),
                      _buildBox(entry.key, entry.value, readOnly),
                    ],
                  ],
                ),
    );
  }

  Widget _buildBox(
      String number, List<_ReceiptItemState> items, bool readOnly) {
    final box = _boxes.cast<Map<String, dynamic>?>().firstWhere(
        (box) => '${box?['boxNumber']}' == number,
        orElse: () => null);
    return Card(
        child: Padding(
            padding: EdgeInsets.all(14.w),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                      'Box $number${box?['label'] == null || '${box?['label']}'.isEmpty ? '' : ' — ${box?['label']}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ]),
              if (box != null)
                Text(
                    'Dimensions: ${box['dimensions'] ?? '-'}  •  Weight: ${box['weight'] ?? '-'} kg',
                    style: TextStyle(
                        fontSize: 12.sp, color: AppColors.textSecondary)),
              for (var index = 0; index < items.length; index += 1)
                _buildItem(items[index], readOnly, index + 1),
            ])));
  }

  Widget _buildItem(_ReceiptItemState item, bool readOnly, int itemNumber) =>
      Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12.r)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#$itemNumber  ${item.item['name'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
                'SN: ${item.item['serialNumber'] ?? '-'}  •  Qty: ${item.item['quantity'] ?? 1}'),
            SizedBox(height: 8.h),
            if (readOnly) ...[
              Text(
                  'Condition: ${item.conditionGood == true ? 'Good' : item.conditionGood == false ? 'Not Good' : '-'}'),
              if (item.notes.text.trim().isNotEmpty)
                Text('Notes: ${item.notes.text.trim()}'),
              if ((item.item['photoIds'] as List? ?? const []).isNotEmpty) ...[
                SizedBox(height: 8.h),
                SizedBox(
                  height: 64.h,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: (item.item['photoIds'] as List).length,
                    separatorBuilder: (_, __) => SizedBox(width: 8.w),
                    itemBuilder: (_, index) {
                      final id = (item.item['photoIds'] as List)[index];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: Image.network(
                          '${AppConstants.baseUrl}/api/incoming/photos/$id',
                          width: 64.w,
                          height: 64.h,
                          fit: BoxFit.cover,
                          headers: _imageHeaders,
                          errorBuilder: (_, __, ___) => const SizedBox.square(
                            dimension: 64,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ] else ...[
              Wrap(spacing: 8.w, children: [
                ChoiceChip(
                    label: const Text('Good'),
                    selected: item.conditionGood == true,
                    onSelected: (_) =>
                        setState(() => item.conditionGood = true)),
                ChoiceChip(
                    label: const Text('Not Good'),
                    selected: item.conditionGood == false,
                    onSelected: (_) =>
                        setState(() => item.conditionGood = false)),
              ]),
              SizedBox(height: 8.h),
              TextField(
                  controller: item.notes,
                  maxLines: 2,
                  maxLength: 255,
                  decoration: const InputDecoration(
                      labelText: 'Condition notes (optional)')),
              TextButton.icon(
                  onPressed: () => _addPhoto(item),
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(
                      'Add photo${item.photos.isEmpty ? '' : ' (${item.photos.length})'}')),
              if (item.photos.isNotEmpty)
                SizedBox(
                    height: 64.h,
                    child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: item.photos.length,
                        separatorBuilder: (_, __) => SizedBox(width: 8.w),
                        itemBuilder: (_, index) => Stack(children: [
                              Image.file(File(item.photos[index].path),
                                  width: 64.w, height: 64.h, fit: BoxFit.cover),
                              Positioned(
                                  right: 0,
                                  child: InkWell(
                                      onTap: () => setState(
                                          () => item.photos.removeAt(index)),
                                      child: const Icon(Icons.cancel,
                                          color: Colors.red)))
                            ]))),
            ],
          ]),
        ),
      );
}

class DnCreatePage extends StatefulWidget {
  final String? presetType;
  final String? presetJobNumber;

  const DnCreatePage({
    Key? key,
    this.presetType,
    this.presetJobNumber,
  }) : super(key: key);

  @override
  State<DnCreatePage> createState() => _DnCreatePageState();
}

class _DnCreatePageState extends State<DnCreatePage> {
  late final Dio _dio;
  bool _loading = true;
  bool _saving = false;
  bool _jobsFallbackOnly = false;
  late String _type;
  List<Map<String, dynamic>> _companies = const [];
  List<Map<String, dynamic>> _jobs = const [];
  List<Map<String, dynamic>> _departments = const [];
  Map<String, dynamic>? _company;
  Map<String, dynamic>? _job;
  Map<String, dynamic>? _department;
  int _counter = 1;
  int _numberRequestId = 0;
  String _numberPreview = '';
  String _sessionUserName = '';

  @override
  void initState() {
    super.initState();
    _type = widget.presetType ?? 'project';
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    _loadData();
  }

  Future<void> _setAuth() async {
    await _setDnAuthHeaders(_dio);
  }

  Future<void> _loadData() async {
    Object? createError;
    try {
      await _setAuth();
      try {
        // Endpoint ini adalah sumber data form Create DAN pada web DN baru.
        final response = await _dio.get('/api/delivery-notes/lookups');
        final data = _dnResponseMap(response.data);
        await _storeDnCreateDataCache(data);
        final companies = (data['companies'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final jobs = (data['jobs'] as List? ?? const []).map((e) {
          final row = Map<String, dynamic>.from(e as Map);
          return {
            ...row,
            'job_number_company': row['companyId'],
            'job_number_code': row['code'],
            'job_number': row['name'],
          };
        }).toList();
        final departments =
            _normalizeDepartments(data['departments'] as List? ?? const []);
        final sessionUser = await AppAuthSession.getStoredUserData();

        setState(() {
          _companies = companies;
          _jobs = jobs;
          _departments = departments;
          _jobsFallbackOnly = false;
          _company = _findSsiCompany(_companies) ??
              (_companies.isNotEmpty ? _companies.first : null);
          _job = _resolvedProjectJobs.isNotEmpty
              ? _resolvedProjectJobs.firstWhere(
                  (row) =>
                      '${row['job_number'] ?? ''}' ==
                      (widget.presetJobNumber ?? ''),
                  orElse: () => _resolvedProjectJobs.first,
                )
              : null;
          _department = _departments.isNotEmpty ? _departments.first : null;
          _sessionUserName = _sessionDisplayName(sessionUser);
        });
      } catch (e) {
        createError = e;
        final cached = await _readDnCreateDataCache();
        if (cached != null && mounted) {
          final companies = (cached['companies'] as List? ??
                  cached['company'] as List? ??
                  const [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final jobs = (cached['jobs'] as List? ??
                  cached['job_numbers'] as List? ??
                  cached['projects'] as List? ??
                  const [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          final departments = _normalizeDepartments(
            cached['departments'] as List? ??
                cached['department_codes'] as List? ??
                const [],
          );
          setState(() {
            _companies = companies;
            _jobs = jobs;
            _departments = departments;
            _company = _findSsiCompany(_companies) ??
                (_companies.isNotEmpty
                    ? _companies.first
                    : _fallbackSsiCompany);
            _job = _resolvedProjectJobs.isNotEmpty
                ? _resolvedProjectJobs.firstWhere(
                    (row) =>
                        '${row['job_number'] ?? ''}' ==
                        (widget.presetJobNumber ?? ''),
                    orElse: () => _resolvedProjectJobs.first,
                  )
                : null;
            _department = _departments.isNotEmpty ? _departments.first : null;
          });
        }
      }

      await _loadGeneralMeta();
      if (_jobs.isEmpty) {
        await _loadJobsFallback();
      }
      if (_company == null && mounted) {
        setState(() {
          _company = _fallbackSsiCompany;
          if (_companies.isEmpty) {
            _companies = [_fallbackSsiCompany];
          }
        });
      }

      if (_type == 'project' &&
          _job == null &&
          _resolvedProjectJobs.isNotEmpty) {
        _job = _resolvedProjectJobs.first;
      }
      if (_type == 'general' &&
          _department == null &&
          _departments.isNotEmpty) {
        _department = _departments.first;
      }

      if (mounted) {
        setState(() => _loading = false);
      }
      await _loadNumber();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      createError ??= e;
    }

    if (createError != null && mounted) {
      _snack(
        _friendlyApiMessage(
          createError!,
          fallback: 'Failed to load DN creation data.',
        ),
        true,
      );
    }
  }

  Future<void> _loadGeneralMeta() async {
    try {
      await _setAuth();
      final response = await _dio.get('/api/inventory/form-data');
      final body = _dnResponseMap(response.data);
      final data = Map<String, dynamic>.from(body['data'] ?? {});
      final departments = _normalizeDepartments(
        data['departments'] as List? ??
            data['inventory_department'] as List? ??
            const [],
      );
      if (!mounted || departments.isEmpty) return;
      setState(() {
        _departments = departments;
        _department ??= departments.first;
      });
    } catch (_) {
      // best effort only
    }
  }

  Future<bool> _loadJobsFallback() async {
    try {
      await _setAuth();
      final response = await _dio.get('/api/projects/list');
      final body = _dnResponseMap(response.data);
      final rows = (body['data'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (rows.isEmpty) return false;
      if (!mounted) return true;
      final fallbackCompanyId =
          '${_effectiveCompanyId ?? AppConstants.defaultDnCompanyId}';
      setState(() {
        _jobs = rows
            .map((row) => {
                  'id': row['id'],
                  'job_number': row['job_number'],
                  'job_number_code': _extractProjectCode(
                      row['cost_code'] ?? row['job_number']),
                  'job_number_company': row['job_number_company'] ??
                      row['company_id'] ??
                      fallbackCompanyId,
                })
            .toList();
        _company ??= _fallbackSsiCompany;
        if (_companies.isEmpty) {
          _companies = [_fallbackSsiCompany];
        }
        _job = _resolvedProjectJobs.firstWhere(
          (row) =>
              '${row['job_number'] ?? ''}' == (widget.presetJobNumber ?? ''),
          orElse: () => _resolvedProjectJobs.isNotEmpty
              ? _resolvedProjectJobs.first
              : _jobs.first,
        );
        _jobsFallbackOnly = true;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadNumber() async {
    final jobId = _type == 'general' ? null : _job?['id'];
    if (_type == 'general' && _departmentCode.isEmpty) return;
    if (_type == 'project' && (jobId == null || '$jobId'.trim().isEmpty))
      return;
    final requestId = ++_numberRequestId;
    await _setAuth();
    final response =
        await _dio.post('/api/delivery-notes/generate-number', data: {
      'mode': _type,
      'jobNumberCompany': _type == 'general' ? 0 : _effectiveCompanyId,
      'jobCode': jobId,
      'departmentCode': _type == 'general' ? _departmentCode : null,
    });
    final body = _dnResponseMap(response.data);
    if (!mounted || requestId != _numberRequestId) return;
    setState(() {
      _counter = int.tryParse('${body['counter'] ?? 1}') ?? 1;
      _numberPreview = '${body['danNumber'] ?? ''}'.trim();
    });
  }

  Future<void> _reloadNumberForSelection() async {
    if (!mounted) return;
    setState(() {
      _counter = 1;
      _numberPreview = '';
    });
    try {
      await _loadNumber();
    } catch (_) {
      // Tombol Create tetap menunjukkan validasi yang jelas bila pilihan belum lengkap.
    }
  }

  String _sessionDisplayName(Map<String, dynamic>? user) {
    if (user == null) return 'pengguna aktif';
    for (final key in const ['name', 'fullName', 'username', 'email']) {
      final value = '${user[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return 'pengguna aktif';
  }

  Map<String, dynamic>? _findSsiCompany(List<Map<String, dynamic>> companies) {
    for (final company in companies) {
      final acronym = '${company['acronym'] ?? ''}'.toUpperCase();
      final name =
          '${company['name'] ?? company['company_name'] ?? ''}'.toUpperCase();
      if (acronym == 'SSI' ||
          name.contains('SEASCAPE SURVEYS INDONESIA') ||
          name == 'SSI') {
        return company;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _normalizeDepartments(List<dynamic> rows) {
    return rows
        .map((item) => Map<String, dynamic>.from(item as Map))
        .map((row) {
          final rawName =
              '${row['description'] ?? row['name'] ?? row['inventory_department'] ?? ''}'
                  .trim();
          String acronym = '${row['acronym'] ?? row['code'] ?? ''}'.trim();
          String description = rawName;
          if (acronym.isEmpty) {
            final match = RegExp(r'^(.*?)-([A-Za-z0-9]+)$').firstMatch(rawName);
            if (match != null) {
              description = match.group(1)!.trim();
              acronym = match.group(2)!.trim();
            }
          }
          if (acronym.isEmpty) {
            acronym = rawName;
          }
          return {
            'id': row['id'] ?? acronym,
            'name': description.isEmpty ? acronym : description,
            'acronym': acronym,
            'display_name':
                description.isEmpty ? acronym : '$description-$acronym',
          };
        })
        .where((row) => '${row['acronym'] ?? ''}'.trim().isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> get _resolvedProjectJobs {
    if (_company == null) return _jobs;
    final companyId = '${_company!['id'] ?? ''}';
    final filtered = _jobs.where((row) {
      final jobCompany =
          '${row['job_number_company'] ?? row['companyId'] ?? row['company_id'] ?? ''}';
      return jobCompany == companyId;
    }).toList();
    return filtered.isNotEmpty ? filtered : _jobs;
  }

  String get _projectAcronym {
    final acronym = '${_company?['acronym'] ?? ''}'.trim();
    return acronym.isEmpty ? 'SSI' : acronym;
  }

  Map<String, dynamic> get _fallbackSsiCompany => {
        'id': AppConstants.defaultDnCompanyId,
        'name': AppConstants.defaultDnCompanyName,
        'company_name': AppConstants.defaultDnCompanyName,
        'acronym': AppConstants.defaultDnCompanyAcronym,
      };

  String? get _effectiveCompanyId {
    final raw =
        '${_company?['id'] ?? _job?['job_number_company'] ?? AppConstants.defaultDnCompanyId}'
            .trim();
    return raw.isEmpty ? null : raw;
  }

  String _extractProjectCode(Object? rawValue) {
    final raw = '$rawValue'.trim();
    final match = RegExp(r'(\d{4,})').firstMatch(raw);
    return match?.group(1) ?? raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  }

  String get _departmentCode {
    final acronym =
        '${_department?['acronym'] ?? _department?['name'] ?? ''}'.trim();
    return acronym.toUpperCase();
  }

  String get _displayCounter {
    final match = RegExp(r'-(\d+)$').firstMatch(_dnNumber.trim());
    return match?.group(1) ?? '$_counter';
  }

  String get _jobCode {
    if (_type == 'general') {
      return _departmentCode;
    }

    final raw =
        '${_job?['job_number_code'] ?? _job?['cost_code'] ?? _job?['job_number'] ?? ''}';
    final match = RegExp(r'(\d{4,})').firstMatch(raw);
    return match?.group(1) ?? raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  }

  String get _dnNumber {
    if (_numberPreview.isNotEmpty) return _numberPreview;
    if (_jobCode.isEmpty) return '-';
    if (_type == 'general') {
      final now = DateTime.now();
      final yy = (now.year % 100).toString().padLeft(2, '0');
      final mm = now.month.toString().padLeft(2, '0');
      return 'SSI-DAN-$_jobCode-$yy$mm-$_counter';
    }
    return '$_projectAcronym-DAN-$_jobCode-$_counter';
  }

  bool get _canSave {
    if (_saving) return false;
    if (_type == 'general') {
      return _department != null &&
          _departmentCode.isNotEmpty &&
          _effectiveCompanyId != null;
    }
    return _job != null && _effectiveCompanyId != null;
  }

  Future<void> _save() async {
    if (!_canSave) {
      _snack(
        _type == 'general'
            ? 'Please select a department code first.'
            : 'Please select a job code first.',
        true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _setAuth();
      final response = await _dio.post('/api/delivery-notes', data: {
        'mode': _type,
        'jobNumberCompany': _type == 'general' ? 0 : _effectiveCompanyId,
        'jobCode': _type == 'general' ? null : _job!['id'],
        'departmentCode': _type == 'general' ? _departmentCode : null,
      });
      final body = _dnResponseMap(response.data);
      final uuid = body['data']?['uuid'];
      if (!mounted) return;
      _snack('Draft DAN dibuat untuk $_sessionUserName.', false);
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DnDetailPage(
            uuid: '$uuid',
            // Preview hanya perkiraan. Nomor resmi tidak boleh ditampilkan
            // sebagai final sebelum pengguna menyelesaikan Finish Dispatch.
            title: 'Draft DAN',
            sampleItem: DnListItem(
              uuid: '$uuid',
              danNumber: 'Draft — assigned on finish',
              jobNumber: _type == 'general'
                  ? _departmentCode
                  : (_job?['job_number']?.toString() ?? _projectAcronym),
              destination: '-',
              dispatchBy: '-',
              receivedBy: '-',
              createdDate: DateTime.now().toIso8601String().split('T').first,
              deliveryDate: '-',
              status: 'Preparation',
              statusId: 1,
            ),
          ),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, changed ?? true);
    } catch (e) {
      _snack(
        _friendlyApiMessage(
          e,
          fallback: 'Failed to create a new DN.',
        ),
        true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.error : AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Create DN'),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'project',
                        label: Text('Project'),
                        icon: Icon(Icons.work_outline)),
                    ButtonSegment(
                        value: 'general',
                        label: Text('General'),
                        icon: Icon(Icons.apartment)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) {
                    setState(() {
                      _type = value.first;
                      _counter = 1;
                      if (_type == 'project') {
                        _company = _findSsiCompany(_companies) ?? _company;
                        _job ??= _resolvedProjectJobs.isNotEmpty
                            ? _resolvedProjectJobs.first
                            : null;
                      } else {
                        _department ??=
                            _departments.isNotEmpty ? _departments.first : null;
                      }
                    });
                    _reloadNumberForSelection();
                  },
                ),
                SizedBox(height: 16.h),
                if (_sessionUserName.isNotEmpty) ...[
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 18),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            'Dibuat oleh: $_sessionUserName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12.sp, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),
                ],
                if (_type == 'project') ...[
                  _dropdown('Company', _company, _companies, (value) {
                    setState(() {
                      _company = value;
                      _job = _resolvedProjectJobs.isNotEmpty
                          ? _resolvedProjectJobs.first
                          : null;
                      _counter = 1;
                      _numberPreview = '';
                    });
                    _reloadNumberForSelection();
                  }, labelKey: 'name'),
                  SizedBox(height: 12.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _dropdown(
                          'Job Code',
                          _job,
                          _resolvedProjectJobs,
                          (value) {
                            setState(() {
                              _job = value;
                              _counter = 1;
                            });
                            _reloadNumberForSelection();
                          },
                          labelKey: 'job_number_code',
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        flex: 2,
                        child: _readOnlyFieldWithLabel('No', _displayCounter),
                      ),
                    ],
                  ),
                ] else ...[
                  _ReadOnlyTile(label: 'Job Number', value: 'General'),
                  SizedBox(height: 12.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _dropdown(
                          'Department Code',
                          _department,
                          _departments,
                          (value) {
                            setState(() {
                              _department = value;
                              _counter = 1;
                            });
                            _reloadNumberForSelection();
                          },
                          labelKey: 'display_name',
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        flex: 2,
                        child: _readOnlyFieldWithLabel('No', _displayCounter),
                      ),
                    ],
                  ),
                ],
                if (_jobsFallbackOnly) ...[
                  SizedBox(height: 8.h),
                  Text(
                    'The job code is currently loaded from project data. Once the DN server list is active, it will sync automatically.',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.warning),
                  ),
                ],
                if (_type == 'project' && _resolvedProjectJobs.isEmpty) ...[
                  SizedBox(height: 8.h),
                  Text(
                    'The job code could not be loaded from the server. Pull to refresh or tap refresh in the top right corner.',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.error),
                  ),
                ],
                if (_type == 'general' && _departments.isEmpty) ...[
                  SizedBox(height: 8.h),
                  Text(
                    'The department code could not be loaded from the server. Pull to refresh or tap refresh in the top right corner.',
                    style: TextStyle(fontSize: 12.sp, color: AppColors.error),
                  ),
                ],
                SizedBox(height: 16.h),
                _ReadOnlyTile(
                  label: 'Next DAN Number Preview',
                  value: _dnNumber == '-' ? 'Assigned on Finish' : _dnNumber,
                ),
                SizedBox(height: 24.h),
                ElevatedButton.icon(
                  onPressed: _canSave ? _save : null,
                  icon: _saving
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save and continue to Customize'),
                ),
              ],
            ),
    );
  }

  Widget _dropdown(
    String label,
    Map<String, dynamic>? value,
    List<Map<String, dynamic>> items,
    ValueChanged<Map<String, dynamic>?> onChanged, {
    required String labelKey,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<Map<String, dynamic>>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      onChanged: enabled ? onChanged : null,
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text('${e[labelKey] ?? '-'}',
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
    );
  }

  Widget _readOnlyFieldWithLabel(String label, String value) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
      ),
    );
  }
}

class DnDetailPage extends StatefulWidget {
  final String uuid;
  final String title;
  final bool useSample;
  final DnListItem? sampleItem;
  final bool forceProcessView;
  final bool forceReadOnly;

  const DnDetailPage({
    Key? key,
    required this.uuid,
    required this.title,
    this.useSample = false,
    this.sampleItem,
    this.forceProcessView = false,
    this.forceReadOnly = false,
  }) : super(key: key);

  @override
  State<DnDetailPage> createState() => _DnDetailPageState();
}

class _DnDetailPageState extends State<DnDetailPage> {
  late final Dio _dio;
  bool _loading = true;
  bool _busy = false;
  bool _jobInfoExpanded = false;
  String? _error;
  bool _apiUnavailable = false;
  Map<String, dynamic>? _dn;
  List<Map<String, dynamic>> _boxes = const [];
  bool _usingSample = false;

  bool get _isReadOnly {
    if (widget.forceReadOnly) return true;
    final status = '${_dn?['status_text'] ?? ''}'.toLowerCase().trim();
    return status == 'sent' ||
        status == 'received' ||
        status.contains('sent') ||
        status.contains('received');
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    _load();
  }

  Future<void> _setAuth() async {
    await _setDnAuthHeaders(_dio);
  }

  Future<void> _setCreateDataAuth() async {
    await _setDnAuthHeaders(_dio, preferStaticToken: true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _apiUnavailable = false;
    });
    try {
      await _setAuth();
      var response = await _dio
          .get('/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}');
      var body = _dnResponseMap(response.data);
      var payload = body['data'];
      if (response.statusCode != 200 || payload is! Map) {
        response = await _dio
            .get('/api/dn/detail/${Uri.encodeComponent(widget.uuid)}');
        body = _dnResponseMap(response.data);
        payload = body['data'];
      }
      if (response.statusCode != 200 || payload is! Map) {
        throw Exception(
            '${body['message'] ?? 'Unable to load Delivery Note details.'}');
      }
      final data = Map<String, dynamic>.from(payload);
      final rawHeader = payload['header'] ?? payload['dn'];
      if (rawHeader is! Map) {
        throw Exception('Invalid Delivery Note detail structure.');
      }
      final header = Map<String, dynamic>.from(rawHeader);
      // Samakan nama field respons web baru dengan field yang dipakai tahapan
      // DN di aplikasi. Nomor tetap kosong/draft sampai Finish Dispatch.
      final normalizedDn = <String, dynamic>{
        ...header,
        'dan_number': '${header['dan_number'] ?? ''}'.trim().isEmpty
            ? 'Assigned on finish'
            : header['dan_number'],
        'status_text':
            '${header['statusLabel'] ?? header['status'] ?? header['status_text'] ?? ''}'
                    .trim()
                    .isEmpty
                ? 'Preparation'
                : header['statusLabel'] ??
                    header['status'] ??
                    header['status_text'],
        'job_number_text': header['jobNumberLabel'] ??
            header['job_number_text'] ??
            header['dan_number_code'] ??
            '-',
        'delivery_address_text': header['destination'] ??
            header['delivery_address_text'] ??
            header['delivery_address'] ??
            header['delivery_address1'] ??
            '-',
        'dispatch_by_name': header['dispatchedByName'] ??
            header['dispatch_by_name'] ??
            header['created_user'] ??
            header['dispatch_by'] ??
            '-',
        'received_by_name': header['receivedByName'] ??
            header['received_by_name'] ??
            header['received_by'] ??
            '-',
      };
      final boxRows = data['boxes'] as List? ?? const [];
      final itemRows = data['items'] as List? ?? const [];
      final normalizedBoxes = itemRows.isNotEmpty
          ? _attachDnItemsToBoxes(boxRows, itemRows)
          : _normalizeDnBoxes(boxRows);
      final mergedBoxes = await _mergeDnBoxesWithCache(
        widget.uuid,
        normalizedBoxes,
      );
      Map<String, List<int>> photoIds = const {};
      try {
        photoIds = await _loadDnItemPhotoIds(_dio, widget.uuid);
      } catch (_) {
        // Foto bersifat tambahan; detail DN tetap harus terbuka bila endpoint foto belum tersedia.
      }
      setState(() {
        _dn = normalizedDn;
        _boxes = _attachDnPhotoIds(mergedBoxes, photoIds);
        _usingSample = false;
        _loading = false;
      });
    } catch (e) {
      if (_shouldUseDnFallback(e)) {
        final synthesized = _buildFallbackDnPayload();
        if (synthesized != null) {
          setState(() {
            _dn = synthesized;
            _boxes = _normalizeDnBoxes(const []);
            _usingSample = true;
            _apiUnavailable = false;
            _loading = false;
          });
          return;
        }
        setState(() {
          _dn = null;
          _boxes = const [];
          _usingSample = false;
          _apiUnavailable = true;
          _error =
              'DN detail is not available because the server endpoint is not active yet.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _dn = null;
        _boxes = const [];
        _usingSample = false;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _buildFallbackDnPayload() {
    if (widget.sampleItem != null) {
      return {
        'uuid': widget.sampleItem!.uuid,
        'dan_number': widget.sampleItem!.danNumber,
        'job_number_text': widget.sampleItem!.jobNumber,
        'delivery_address_text': widget.sampleItem!.destination,
        'dispatch_by_name': widget.sampleItem!.dispatchBy,
        'received_by_name': widget.sampleItem!.receivedBy,
        'delivery_date': widget.sampleItem!.deliveryDate,
        'status_text': widget.sampleItem!.status,
        'dan_number_department':
            _inferDepartmentCode(widget.sampleItem!.danNumber),
      };
    }

    final title = widget.title.trim();
    if (title.isEmpty) return null;

    final isGeneral = title.contains('-TAX-') || title.contains('-GEN-');
    return {
      'uuid': widget.uuid,
      'dan_number': title,
      'job_number_text': isGeneral ? 'General' : '-',
      'delivery_address_text': '-',
      'dispatch_by_name': '-',
      'received_by_name': '-',
      'delivery_date': '-',
      'status_text': 'Preparation',
      'dan_number_department': isGeneral ? _inferDepartmentCode(title) : '',
    };
  }

  String _inferDepartmentCode(String dnNumber) {
    final match =
        RegExp(r'^SSI-DAN-([A-Z]+)-').firstMatch(dnNumber.trim().toUpperCase());
    return match?.group(1) ?? '';
  }

  Future<void> _addBox() async {
    if (_isReadOnly) {
      _snack('DN berstatus ${_dn?['status_text'] ?? '-'} dan sudah readonly.',
          true);
      return;
    }
    await _setAuth();
    await _run(() async {
      final response = await _dio.post(
          '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/boxes');
      if (response.statusCode != 201) {
        final body = _dnResponseMap(response.data);
        throw Exception('${body['message'] ?? 'Unable to create the box.'}');
      }
      return response;
    }, success: 'Box added successfully. Add at least one item to continue.');
    await _load();
  }

  bool get _hasAtLeastOneItem => _boxes.any(
        (box) => (box['items'] as List? ?? const []).isNotEmpty,
      );

  Future<void> _continueToSender() async {
    if (!_hasAtLeastOneItem) {
      _snack('Add at least one item to the box before continuing.', true);
      return;
    }
    await _openSender();
  }

  Future<void> _openSender() async {
    if (!_hasAtLeastOneItem) {
      _snack('Add at least one item to the box before continuing.', true);
      return;
    }
    if (_isReadOnly) {
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DnSenderPage(
            uuid: widget.uuid,
            dnTitle: widget.title,
            currentDn: _dn ?? const {},
            currentBoxes: _boxes,
            useSample: _usingSample,
            readOnly: true,
          ),
        ),
      );
      if (changed == true) {
        _load();
      }
      return;
    }

    final isPreparation =
        '${_dn?['status_text'] ?? ''}'.toLowerCase() == 'preparation';
    if (isPreparation) {
      final confirmed = await _confirmProceed(
        title: 'Continue to Sender?',
        message:
            'This DN is still in Preparation status. Please make sure the boxes and items are complete before continuing to the sender step.',
        confirmLabel: 'Yes, continue',
      );
      if (confirmed != true) return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DnSenderPage(
          uuid: widget.uuid,
          dnTitle: widget.title,
          currentDn: _dn ?? const {},
          currentBoxes: _boxes,
          useSample: _usingSample,
          readOnly: false,
        ),
      ),
    );
    if (changed == true) {
      _load();
    }
  }

  Future<bool?> _confirmProceed({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Future<Response<dynamic>> Function() action,
      {String success = 'Data saved successfully.'}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _snack(success, false);
    } catch (e) {
      if (!mounted) return;
      _snack('Failed: $e', true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.error : AppColors.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = '${_dn?['status_text'] ?? '-'}';
    final fallbackDn = _buildFallbackDnPayload();
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.lightBackground,
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _apiUnavailable && fallbackDn != null
                ? ListView(
                    padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                    children: [
                      _StepHeader(
                          status:
                              '${fallbackDn['status_text'] ?? 'Preparation'}'),
                      SizedBox(height: 12.h),
                      _JobInfo(
                        dn: fallbackDn,
                        expanded: _jobInfoExpanded,
                        onToggle: () => setState(
                            () => _jobInfoExpanded = !_jobInfoExpanded),
                      ),
                      SizedBox(height: 12.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Add Box'),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _busy || !_hasAtLeastOneItem
                                  ? null
                                  : _continueToSender,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Next'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      const _EmptyBox(),
                    ],
                  )
                : _apiUnavailable
                    ? _ApiUnavailableState(message: _error!, onRetry: _load)
                    : _error != null
                        ? _ErrorState(message: _error!, onRetry: _load)
                        : ListView(
                            padding:
                                EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 100.h),
                            children: [
                              _StepHeader(status: status),
                              SizedBox(height: 12.h),
                              _JobInfo(
                                dn: _dn ?? const {},
                                expanded: _jobInfoExpanded,
                                onToggle: () => setState(
                                    () => _jobInfoExpanded = !_jobInfoExpanded),
                              ),
                              SizedBox(height: 12.h),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed:
                                          _busy || _isReadOnly ? null : _addBox,
                                      icon: const Icon(
                                          Icons.inventory_2_outlined),
                                      label: const Text('Add Box'),
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _busy ||
                                              (!_isReadOnly &&
                                                  !_hasAtLeastOneItem)
                                          ? null
                                          : _continueToSender,
                                      icon: Icon(_isReadOnly
                                          ? Icons.visibility_outlined
                                          : Icons.arrow_forward_rounded),
                                      label:
                                          Text(_isReadOnly ? 'Review' : 'Next'),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12.h),
                              if (_boxes.isEmpty)
                                const _EmptyBox()
                              else
                                ..._boxes.map(
                                  (box) => _BoxCard(
                                    uuid: widget.uuid,
                                    box: box,
                                    dio: _dio,
                                    onChanged: _load,
                                    onMessage: _snack,
                                    useSample: _usingSample,
                                    readOnly: _isReadOnly,
                                  ),
                                ),
                            ],
                          ),
      ),
    );
  }
}

class _BoxCard extends StatefulWidget {
  final String uuid;
  final Map<String, dynamic> box;
  final Dio dio;
  final VoidCallback onChanged;
  final void Function(String, bool) onMessage;
  final bool useSample;
  final bool readOnly;

  const _BoxCard({
    required this.uuid,
    required this.box,
    required this.dio,
    required this.onChanged,
    required this.onMessage,
    this.useSample = false,
    this.readOnly = false,
  });

  @override
  State<_BoxCard> createState() => _BoxCardState();
}

class _BoxCardState extends State<_BoxCard> {
  bool _expanded = false;

  Future<void> _editBox() async {
    if (widget.readOnly) {
      widget.onMessage(
          'This DN is read-only, so the box cannot be edited.', true);
      return;
    }
    final labelController =
        TextEditingController(text: '${widget.box['box_label'] ?? ''}');
    final dimController =
        TextEditingController(text: '${widget.box['box_dim'] ?? ''}');
    final weightController =
        TextEditingController(text: '${widget.box['box_weight'] ?? ''}');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 20.h),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                Text('Edit BOX${widget.box['box_number']}',
                    style: TextStyle(
                        fontSize: 18.sp, fontWeight: FontWeight.w800)),
                SizedBox(height: 14.h),
                TextField(
                    controller: labelController,
                    decoration: const InputDecoration(labelText: 'Label')),
                SizedBox(height: 10.h),
                TextField(
                  controller: dimController,
                  decoration: const InputDecoration(
                    labelText: 'Dimensions',
                    hintText: 'Length × Width × Height (cm)',
                  ),
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Weight', hintText: 'Weight (kg)'),
                ),
                SizedBox(height: 10.h),
                SizedBox(height: 16.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (saved != true) return;
    if (widget.useSample) {
      widget.box['box_label'] = labelController.text;
      widget.box['box_dim'] = dimController.text;
      widget.box['box_weight'] = weightController.text;
      widget.onMessage('Mode sample: perubahan box hanya tampilan.', false);
      setState(() {});
      return;
    }
    try {
      final boxNumber = Uri.encodeComponent('${widget.box['box_number']}');
      final response = await widget.dio.patch(
          '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/boxes/$boxNumber',
          data: {
            'label': labelController.text,
            'dim': dimController.text,
            'weight': weightController.text,
          });
      if (response.statusCode != 200) {
        final body = _dnResponseMap(response.data);
        throw Exception('${body['message'] ?? 'Unable to save the box.'}');
      }
      // PATCH sukses, maka kartu yang sedang terbuka juga harus diperbarui
      // tanpa menunggu halaman detail dimuat ulang.
      widget.box['box_label'] = labelController.text.trim();
      widget.box['box_dim'] = dimController.text.trim();
      widget.box['box_weight'] = weightController.text.trim().isEmpty
          ? '0'
          : weightController.text.trim();
      if (mounted) setState(() {});
      widget.onMessage('Box saved successfully.', false);
      widget.onChanged();
    } catch (e) {
      widget.onMessage('Failed to save box: $e', true);
    }
  }

  Future<void> _openItemsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DnBoxItemsPage(
          uuid: widget.uuid,
          box: widget.box,
          dio: widget.dio,
          useSample: widget.useSample,
          readOnly: widget.readOnly,
        ),
      ),
    );
    widget.onChanged();
  }

  Future<void> _deleteItem(dynamic id) async {
    if (widget.readOnly) {
      widget.onMessage(
          'This DN is read-only, so the item cannot be deleted.', true);
      return;
    }
    if (widget.useSample) {
      final items = (widget.box['items'] as List? ?? <Map<String, dynamic>>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      items.removeWhere((item) => '${item['id']}' == '$id');
      widget.box['items'] = items;
      await _rememberDnBoxItems(widget.uuid, widget.box['box_number'], items);
      setState(() {});
      widget.onMessage('Item deleted from the current box.', false);
      return;
    }
    try {
      await widget.dio.post('/api/dn/item/delete',
          data: {'uuid': widget.uuid, 'item_id': id});
      final items = (widget.box['items'] as List? ?? <Map<String, dynamic>>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      items.removeWhere((item) => '${item['id']}' == '$id');
      widget.box['items'] = items;
      await _rememberDnBoxItems(widget.uuid, widget.box['box_number'], items);
      widget.onMessage('Item deleted successfully.', false);
      widget.onChanged();
    } catch (e) {
      widget.onMessage('Failed to delete item: $e', true);
    }
  }

  Future<void> _deleteBox() async {
    if (widget.readOnly) {
      widget.onMessage(
          'This DN is read-only, so the box cannot be deleted.', true);
      return;
    }
    try {
      await widget.dio.post('/api/dn/box/delete', data: {
        'uuid': widget.uuid,
        'box_number': widget.box['box_number'],
      });
      widget.onMessage('Box deleted successfully.', false);
      widget.onChanged();
    } catch (e) {
      widget.onMessage('Failed to delete box: $e', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boxNo = widget.box['box_number'];
    final items = (widget.box['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final label = '${widget.box['box_label'] ?? ''}'.trim();
    final dim = '${widget.box['box_dim'] ?? ''}'.trim();
    final weight = '${widget.box['box_weight'] ?? '0'}';
    return Card(
      margin: EdgeInsets.only(bottom: 14.h),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('BOX$boxNo',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16.sp))),
                if (!widget.readOnly)
                  IconButton(
                    onPressed: _editBox,
                    icon: const Icon(Icons.edit_note_rounded),
                  ),
                if (!widget.readOnly)
                  IconButton(
                    onPressed: _deleteBox,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.error),
                  ),
                IconButton(
                  onPressed: widget.readOnly
                      ? () => setState(() => _expanded = !_expanded)
                      : _openItemsPage,
                  icon: Icon(widget.readOnly && _expanded
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  tooltip: widget.readOnly
                      ? (_expanded
                          ? 'Sembunyikan detail box'
                          : 'Lihat detail box')
                      : 'Lihat item',
                ),
              ],
            ),
            if (!widget.readOnly || _expanded) ...[
              SizedBox(height: 10.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  _boxChip('Label: ${label.isEmpty ? '-' : label}'),
                  _boxChip('Item: ${items.length}'),
                  _boxChip('Weight: $weight kg'),
                  if (dim.isNotEmpty) _boxChip('DIM: $dim'),
                ],
              ),
              SizedBox(height: 12.h),
              if (items.isEmpty)
                const ListTile(
                    leading: Icon(Icons.inbox_outlined),
                    title: Text('No items yet'))
              else
                ...items.map((item) {
                  final name = _equipmentDisplayName(item);
                  final sn = '${item['equipment_sn'] ?? item['sn'] ?? '-'}';
                  return Container(
                    margin: EdgeInsets.only(bottom: 10.h),
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48.w,
                          height: 48.w,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: _DnItemPhotoButton(
                            dio: widget.dio,
                            uuid: widget.uuid,
                            item: item,
                            readOnly: widget.readOnly,
                            onChanged: widget.onChanged,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'SN: $sn',
                                style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textSecondary),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'Qty: ${item['equipment_qty'] ?? 1}',
                                style: TextStyle(
                                    fontSize: 12.sp,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (!widget.readOnly)
                          IconButton(
                            onPressed: () => _deleteItem(item['id']),
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.error),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _boxChip(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _OtherItemDialog extends StatefulWidget {
  const _OtherItemDialog();

  @override
  State<_OtherItemDialog> createState() => _OtherItemDialogState();
}

class DnBoxItemsPage extends StatefulWidget {
  final String uuid;
  final Map<String, dynamic> box;
  final Dio dio;
  final bool useSample;
  final bool readOnly;

  const DnBoxItemsPage({
    Key? key,
    required this.uuid,
    required this.box,
    required this.dio,
    required this.useSample,
    required this.readOnly,
  }) : super(key: key);

  @override
  State<DnBoxItemsPage> createState() => _DnBoxItemsPageState();
}

class _DnBoxItemsPageState extends State<DnBoxItemsPage> {
  List<Map<String, dynamic>> get _items => _normalizeDnItems(
        (widget.box['items'] as List? ?? const []).whereType<Map>().toList(),
      );

  Future<void> _refreshPhotoIds() async {
    try {
      final photoIds = await _loadDnItemPhotoIds(widget.dio, widget.uuid);
      final items = _items.map((item) {
        final ids = photoIds['${item['id'] ?? ''}'] ?? const <int>[];
        return {...item, 'photo_ids': ids, 'photo_count': ids.length};
      }).toList();
      widget.box['items'] = items;
      if (mounted) setState(() {});
    } catch (_) {
      // The photo action already shows its own error message.
    }
  }

  Future<void> _deleteItem(dynamic id) async {
    if (widget.readOnly) return;

    if (widget.useSample) {
      final items = _items;
      items.removeWhere((item) => '${item['id']}' == '$id');
      widget.box['items'] = items;
      await _rememberDnBoxItems(widget.uuid, widget.box['box_number'], items);
      if (mounted) setState(() {});
      return;
    }

    try {
      await widget.dio.post('/api/dn/item/delete', data: {
        'uuid': widget.uuid,
        'item_id': id,
      });
      final items = _items;
      items.removeWhere((item) => '${item['id']}' == '$id');
      widget.box['items'] = items;
      await _rememberDnBoxItems(widget.uuid, widget.box['box_number'], items);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete item: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openAddEquipmentPage() async {
    if (widget.readOnly) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DnEquipmentPage(
          uuid: widget.uuid,
          box: widget.box,
          dio: widget.dio,
          useSample: widget.useSample,
          readOnly: widget.readOnly,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _openAddOtherPage() async {
    if (widget.readOnly) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DnOtherItemPage(
          uuid: widget.uuid,
          box: widget.box,
          dio: widget.dio,
          useSample: widget.useSample,
          readOnly: widget.readOnly,
        ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text('BOX${widget.box['box_number']} Items'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        children: [
          _BoxSummaryRow(
              label: 'Label', value: '${widget.box['box_label'] ?? '-'}'),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                  child: _BoxSummaryRow(
                      label: 'DIM', value: '${widget.box['box_dim'] ?? '-'}')),
              SizedBox(width: 10.w),
              Expanded(
                  child: _BoxSummaryRow(
                      label: 'Weight',
                      value: '${widget.box['box_weight'] ?? '0'}')),
            ],
          ),
          SizedBox(height: 16.h),
          Text('Items in Box',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 10.h),
          if (_items.isEmpty)
            const ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('No items yet'),
            )
          else
            ..._items.map((item) {
              final name = _equipmentDisplayName(item);
              final sn = '${item['equipment_sn'] ?? item['sn'] ?? '-'}';
              return Card(
                child: ListTile(
                  leading: _DnItemPhotoButton(
                    dio: widget.dio,
                    uuid: widget.uuid,
                    item: item,
                    readOnly: widget.readOnly,
                    onChanged: _refreshPhotoIds,
                  ),
                  title: Text(name),
                  subtitle: Text('SN: $sn\nQty: ${item['equipment_qty'] ?? 1}'),
                  isThreeLine: true,
                  trailing: widget.readOnly
                      ? null
                      : IconButton(
                          onPressed: () => _deleteItem(item['id']),
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.error),
                        ),
                ),
              );
            }),
        ],
      ),
      bottomNavigationBar: widget.readOnly
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openAddEquipmentPage,
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      label: const Text('Add Equipment'),
                    ),
                  ),
                  SizedBox(height: 10.h),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openAddOtherPage,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Add Other Item'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class DnSenderPage extends StatefulWidget {
  final String uuid;
  final String dnTitle;
  final Map<String, dynamic> currentDn;
  final List<Map<String, dynamic>> currentBoxes;
  final bool useSample;
  final bool readOnly;

  const DnSenderPage({
    Key? key,
    required this.uuid,
    required this.dnTitle,
    required this.currentDn,
    required this.currentBoxes,
    required this.useSample,
    required this.readOnly,
  }) : super(key: key);

  @override
  State<DnSenderPage> createState() => _DnSenderPageState();
}

class _DnSenderPageState extends State<DnSenderPage> {
  late final Dio _dio;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _apiUnavailable = false;
  bool _manualAddressMode = false;
  List<Map<String, dynamic>> _addresses = const [];
  List<Map<String, dynamic>> _senderOptions = const [];
  List<Map<String, dynamic>> _receiverOptions = const [];
  List<Map<String, dynamic>> _usage = const [];
  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _proformaNames = const [];
  List<Map<String, dynamic>> _currencies = const [];

  Map<String, dynamic>? _sender;
  Map<String, dynamic>? _receiver;
  Map<String, dynamic>? _usageValue;
  Map<String, dynamic>? _locationValue;
  Map<String, dynamic>? _proformaName;
  Map<String, dynamic>? _currency;
  bool _signDispatch = true;

  final _attn = TextEditingController();
  final _senderAddress = TextEditingController();
  final _receiverAddress = TextEditingController();
  final _senderTelp = TextEditingController();
  final _senderFax = TextEditingController();
  final _attnTelp = TextEditingController();
  final _specialInstruction = TextEditingController();
  final _deliveryDate = TextEditingController();
  final _customDestinationLocation = TextEditingController();

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    _load();
  }

  @override
  void dispose() {
    _attn.dispose();
    _senderAddress.dispose();
    _receiverAddress.dispose();
    _senderTelp.dispose();
    _senderFax.dispose();
    _attnTelp.dispose();
    _specialInstruction.dispose();
    _deliveryDate.dispose();
    _customDestinationLocation.dispose();
    super.dispose();
  }

  Future<void> _setAuth() async {
    await _setDnAuthHeaders(_dio);
  }

  Future<void> _setCreateDataAuth() async {
    await _setDnAuthHeaders(_dio, preferStaticToken: true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _apiUnavailable = false;
      _manualAddressMode = false;
    });
    try {
      await _setAuth();
      if (widget.useSample) {
        setState(() {
          _apiUnavailable = true;
          _error =
              'Sender data is not available because the DN API is still using a fallback with no demo data.';
          _loading = false;
        });
        return;
      }
      // Lookup yang sama dengan wizard DN web baru.
      final response = await _dio.get('/api/delivery-notes/lookups');
      final body = _dnResponseMap(response.data);
      final lookupPayload = body['data'] is Map ? body['data'] : body;
      final data = Map<String, dynamic>.from(lookupPayload as Map);
      await _storeDnCreateDataCache(data);
      var addresses =
          _normalizeDnAddresses(data['addresses'] as List? ?? const []);
      if (addresses.isEmpty) {
        final cached = await _readDnCreateDataCache();
        if (cached != null) {
          final cachedAddresses =
              _normalizeDnAddresses(cached['addresses'] as List? ?? const []);
          if (cachedAddresses.isNotEmpty) {
            addresses = cachedAddresses;
          }
        }
      }
      final senderFallbackOption =
          _dnAddressOptionFromCurrent(widget.currentDn, sender: true);
      final receiverFallbackOption =
          _dnAddressOptionFromCurrent(widget.currentDn, sender: false);
      final senderAddressOptions = _senderAddressOptions(addresses).isNotEmpty
          ? _senderAddressOptions(addresses)
          : [if (senderFallbackOption != null) senderFallbackOption];
      final receiverAddressOptions =
          _receiverAddressOptions(addresses).isNotEmpty
              ? _receiverAddressOptions(addresses)
              : [if (receiverFallbackOption != null) receiverFallbackOption];
      final senderOptions = [
        ...senderAddressOptions,
        {'id': 'other', 'name': 'Other / Custom Address'}
      ];
      final receiverOptions = [
        ...receiverAddressOptions,
        {'id': 'other', 'name': 'Other / Custom Address'}
      ];
      final senderId = '${widget.currentDn['delivery_seascape'] ?? ''}';
      final receiverId = '${widget.currentDn['sender_seascape'] ?? ''}';
      final usageId =
          '${widget.currentDn['destination_usage_id'] ?? widget.currentDn['eq_usage'] ?? ''}';
      final locationId =
          '${widget.currentDn['destination_location_id'] ?? widget.currentDn['eq_location'] ?? ''}';
      final proformaNameId = '${widget.currentDn['proforma_name_id'] ?? ''}';
      final currencyId = '${widget.currentDn['proforma_currency_id'] ?? ''}';
      final usageItems = (data['usage'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final locationItems = (data['locations'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final proformaNameItems = (data['proformaNames'] as List? ??
              data['proforma_names'] as List? ??
              const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final currencyItems = (data['currencies'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _addresses = addresses;
        _senderOptions = senderOptions.isNotEmpty ? senderOptions : addresses;
        _receiverOptions =
            receiverOptions.isNotEmpty ? receiverOptions : addresses;
        _usage = [
          ...usageItems,
          {'id': 'other', 'name': 'Other'}
        ];
        _locations = locationItems;
        _proformaNames = proformaNameItems;
        _currencies = currencyItems;
        // DN baru harus dimulai tanpa Sender, To, dan Usage yang terpilih.
        // Nilai hanya diisi kembali bila sebelumnya memang pernah disimpan.
        _sender = senderId.isEmpty
            ? null
            : _senderOptions.cast<Map<String, dynamic>?>().firstWhere(
                  (e) => '${e?['id'] ?? ''}' == senderId,
                  orElse: () => null,
                );
        _receiver = receiverId.isEmpty
            ? null
            : _receiverOptions.cast<Map<String, dynamic>?>().firstWhere(
                  (e) => '${e?['id'] ?? ''}' == receiverId,
                  orElse: () => null,
                );
        _usageValue = usageId.isEmpty
            ? null
            : _usage.cast<Map<String, dynamic>?>().firstWhere(
                  (e) => '${e?['id'] ?? ''}' == usageId,
                  orElse: () => null,
                );
        _locationValue = _locations.firstWhere(
          (e) => '${e['id'] ?? ''}' == locationId,
          orElse: () => <String, dynamic>{},
        );
        _proformaName = _proformaNames.firstWhere(
          (e) => '${e['id'] ?? ''}' == proformaNameId,
          orElse: () => _proformaNames.isNotEmpty
              ? _proformaNames.first
              : <String, dynamic>{},
        );
        _currency = _currencies.firstWhere(
          (e) => '${e['id'] ?? ''}' == currencyId,
          orElse: () =>
              _currencies.isNotEmpty ? _currencies.first : <String, dynamic>{},
        );
        if ((_locationValue?['id'] ?? '').toString().isEmpty) {
          _locationValue = null;
        }
        if ((_proformaName?['id'] ?? '').toString().isEmpty) {
          _proformaName =
              _proformaNames.isNotEmpty ? _proformaNames.first : null;
        }
        if ((_currency?['id'] ?? '').toString().isEmpty) {
          _currency = _currencies.isNotEmpty ? _currencies.first : null;
        }
        _senderAddress.text = _firstNonEmptyValue(
          widget.currentDn,
          ['sender_address'],
          fallback: _sender == null ? '' : _addressTextFromRow(_sender),
        );
        _receiverAddress.text = _firstNonEmptyValue(
          widget.currentDn,
          ['delivery_address'],
          fallback: _receiver == null ? '' : _addressTextFromRow(_receiver),
        );
        _senderTelp.text = _firstNonEmptyValue(
          widget.currentDn,
          ['sender_tel', 'sender_telp'],
          fallback: '${_sender?['telp'] ?? ''}',
        );
        _senderFax.text = _firstNonEmptyValue(
          widget.currentDn,
          ['sender_fax'],
          fallback: '${_sender?['fax'] ?? ''}',
        );
        _attn.text = '${widget.currentDn['attn'] ?? ''}';
        _attnTelp.text = '${widget.currentDn['attn_telp'] ?? ''}';
        _specialInstruction.text =
            '${widget.currentDn['special_instruction'] ?? ''}';
        _deliveryDate.text = '${widget.currentDn['delivery_date'] ?? ''}'
                .replaceAll('-', '')
                .isEmpty
            ? ''
            : '${widget.currentDn['delivery_date']}';
        _customDestinationLocation.text = '';
        _signDispatch = '${widget.currentDn['sign_dispatch'] ?? '1'}' == '1';
        _manualAddressMode = false;
        _loading = false;
      });
    } catch (e) {
      final cached = await _readDnCreateDataCache();
      if (cached != null) {
        final addresses =
            _normalizeDnAddresses(cached['addresses'] as List? ?? const []);
        final senderFallbackOption =
            _dnAddressOptionFromCurrent(widget.currentDn, sender: true);
        final receiverFallbackOption =
            _dnAddressOptionFromCurrent(widget.currentDn, sender: false);
        final senderOptions = _senderAddressOptions(addresses).isNotEmpty
            ? _senderAddressOptions(addresses)
            : [if (senderFallbackOption != null) senderFallbackOption];
        final receiverOptions = _receiverAddressOptions(addresses).isNotEmpty
            ? _receiverAddressOptions(addresses)
            : [if (receiverFallbackOption != null) receiverFallbackOption];
        final usageItems = (cached['usage'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final locationItems = (cached['locations'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final proformaNameItems =
            (cached['proforma_names'] as List? ?? const [])
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
        final currencyItems = (cached['currencies'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final senderId = '${widget.currentDn['sender_seascape'] ?? ''}';
        final receiverId = '${widget.currentDn['delivery_seascape'] ?? ''}';
        final usageId = '${widget.currentDn['eq_usage'] ?? ''}';
        final locationId = '${widget.currentDn['eq_location'] ?? ''}';
        final proformaNameId = '${widget.currentDn['proforma_name_id'] ?? ''}';
        final currencyId = '${widget.currentDn['proforma_currency_id'] ?? ''}';
        if (mounted) {
          setState(() {
            _addresses = addresses;
            _senderOptions =
                senderOptions.isNotEmpty ? senderOptions : addresses;
            _receiverOptions =
                receiverOptions.isNotEmpty ? receiverOptions : addresses;
            _usage = usageItems;
            _locations = locationItems;
            _proformaNames = proformaNameItems;
            _currencies = currencyItems;
            _sender = _senderOptions.firstWhere(
              (item) => '${item['id'] ?? ''}' == senderId,
              orElse: () => _senderOptions.isNotEmpty
                  ? _senderOptions.first
                  : <String, dynamic>{},
            );
            _receiver = _receiverOptions.firstWhere(
              (item) => '${item['id'] ?? ''}' == receiverId,
              orElse: () => _receiverOptions.isNotEmpty
                  ? _receiverOptions.first
                  : <String, dynamic>{},
            );
            if (senderId.isEmpty) _sender = null;
            if (receiverId.isEmpty) _receiver = null;
            _usageValue = _usage.firstWhere(
              (item) => '${item['id'] ?? ''}' == usageId,
              orElse: () =>
                  _usage.isNotEmpty ? _usage.first : <String, dynamic>{},
            );
            if (usageId.isEmpty) _usageValue = null;
            _locationValue = _locations.firstWhere(
              (item) => '${item['id'] ?? ''}' == locationId,
              orElse: () => _locations.isNotEmpty
                  ? _locations.first
                  : <String, dynamic>{},
            );
            _proformaName = _proformaNames.firstWhere(
              (item) => '${item['id'] ?? ''}' == proformaNameId,
              orElse: () => _proformaNames.isNotEmpty
                  ? _proformaNames.first
                  : <String, dynamic>{},
            );
            _currency = _currencies.firstWhere(
              (item) => '${item['id'] ?? ''}' == currencyId,
              orElse: () => _currencies.isNotEmpty
                  ? _currencies.first
                  : <String, dynamic>{},
            );
            _senderAddress.text = _firstNonEmptyValue(
              widget.currentDn,
              ['sender_address'],
              fallback: _addressTextFromRow(_sender),
            );
            _receiverAddress.text = _firstNonEmptyValue(
              widget.currentDn,
              ['delivery_address'],
              fallback: _addressTextFromRow(_receiver),
            );
            _senderTelp.text = _firstNonEmptyValue(
              widget.currentDn,
              ['sender_tel', 'sender_telp'],
              fallback: '${_sender?['telp'] ?? ''}',
            );
            _senderFax.text = _firstNonEmptyValue(
              widget.currentDn,
              ['sender_fax'],
              fallback: '${_sender?['fax'] ?? ''}',
            );
            _attn.text = '${widget.currentDn['attn'] ?? ''}';
            _attnTelp.text = '${widget.currentDn['attn_telp'] ?? ''}';
            _specialInstruction.text =
                '${widget.currentDn['special_instruction'] ?? ''}';
            _deliveryDate.text = '${widget.currentDn['delivery_date'] ?? ''}';
            _signDispatch =
                '${widget.currentDn['sign_dispatch'] ?? '1'}' == '1';
            _manualAddressMode = false;
            _error =
                'Sender data was loaded from the last cache because the server endpoint is unstable.';
            _loading = false;
          });
          return;
        }
      }
      if (_shouldUseDnFallback(e)) {
        List<Map<String, dynamic>> usageItems = const [];
        List<Map<String, dynamic>> locationItems = const [];
        try {
          await _setAuth();
          final response = await _dio.get('/api/inventory/form-data');
          final body = _dnResponseMap(response.data);
          final data = Map<String, dynamic>.from(body['data'] ?? {});
          usageItems = (data['inventory_usage'] as List? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
          locationItems = (data['inventory_location'] as List? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } catch (_) {
          // keep manual mode with empty master data
        }
        setState(() {
          final senderFallbackOption =
              _dnAddressOptionFromCurrent(widget.currentDn, sender: true);
          final receiverFallbackOption =
              _dnAddressOptionFromCurrent(widget.currentDn, sender: false);
          _senderOptions = [
            if (senderFallbackOption != null) senderFallbackOption
          ];
          _receiverOptions = [
            if (receiverFallbackOption != null) receiverFallbackOption
          ];
          _sender = _senderOptions.isNotEmpty ? _senderOptions.first : null;
          _receiver =
              _receiverOptions.isNotEmpty ? _receiverOptions.first : null;
          _usage = usageItems;
          _locations = locationItems;
          _senderAddress.text = _firstNonEmptyValue(
            widget.currentDn,
            ['sender_address'],
            fallback: _addressTextFromRow(_sender),
          );
          _receiverAddress.text = _firstNonEmptyValue(
            widget.currentDn,
            ['delivery_address'],
            fallback: _addressTextFromRow(_receiver),
          );
          _senderTelp.text =
              '${widget.currentDn['sender_tel'] ?? widget.currentDn['sender_telp'] ?? _sender?['telp'] ?? ''}';
          _senderFax.text =
              '${widget.currentDn['sender_fax'] ?? _sender?['fax'] ?? ''}';
          _attn.text = '${widget.currentDn['attn'] ?? ''}';
          _attnTelp.text = '${widget.currentDn['attn_telp'] ?? ''}';
          _specialInstruction.text =
              '${widget.currentDn['special_instruction'] ?? ''}';
          _deliveryDate.text = '${widget.currentDn['delivery_date'] ?? ''}';
          _signDispatch = '${widget.currentDn['sign_dispatch'] ?? '1'}' == '1';
          _usageValue = usageItems.firstWhere(
            (item) =>
                '${item['id'] ?? ''}' ==
                '${widget.currentDn['eq_usage'] ?? ''}',
            orElse: () =>
                usageItems.isNotEmpty ? usageItems.first : <String, dynamic>{},
          );
          _locationValue = locationItems.firstWhere(
            (item) =>
                '${item['id'] ?? ''}' ==
                '${widget.currentDn['eq_location'] ?? ''}',
            orElse: () => locationItems.isNotEmpty
                ? locationItems.first
                : <String, dynamic>{},
          );
          if ((_usageValue?['id'] ?? '').toString().isEmpty) {
            _usageValue = usageItems.isNotEmpty ? usageItems.first : null;
          }
          if ((_locationValue?['id'] ?? '').toString().isEmpty) {
            _locationValue =
                locationItems.isNotEmpty ? locationItems.first : null;
          }
          _manualAddressMode = true;
          _error =
              'Sender master data has not been loaded from the server yet. The form can still be filled manually.';
          _loading = false;
        });
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveAndNext() async {
    if (widget.readOnly) {
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DnReviewPage(
            uuid: widget.uuid,
            dnTitle: widget.dnTitle,
            currentDn: widget.currentDn,
            currentBoxes: widget.currentBoxes,
            senderName:
                '${_sender?['name'] ?? _sender?['company_name'] ?? '-'}',
            receiverName:
                '${_receiver?['name'] ?? _receiver?['company_name'] ?? '-'}',
            deliveryDate: _deliveryDate.text.trim(),
            useSample: false,
            readOnly: true,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, changed ?? true);
      return;
    }

    final validationError = _senderValidationError();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(validationError), backgroundColor: AppColors.error),
      );
      return;
    }

    final confirmed = await _confirmProceed();
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await _setAuth();
      // Field dan endpoint sama dengan langkah Sender pada wizard DN web.
      final response = await _dio.put(
          '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}',
          data: {
            'senderCompanyId': _sender?['id'],
            'receiverCompanyId': _receiver?['id'],
            'senderAddress': _senderAddress.text.trim(),
            'senderTel': _senderTelp.text.trim(),
            'senderFax': _senderFax.text.trim(),
            'deliveryAddress': _receiverAddress.text.trim(),
            'attn': _attn.text.trim(),
            'attnTelp': _attnTelp.text.trim(),
            'destinationUsageId': _usageValue?['id'],
            'destinationLocationId': _locationValue?['id'],
            'customDestinationLocation': _customDestinationLocation.text.trim(),
            'specialInstruction': _specialInstruction.text.trim(),
            'deliveryDate': _deliveryDate.text.trim(),
            'proformaNameId': _proformaName?['id'],
            'proformaNumber': widget.currentDn['proforma_number'] ?? '',
            'proformaCounter': widget.currentDn['proforma_counter'] ?? 0,
            'proformaCurrencyId': _currency?['id'],
          });
      if (response.statusCode != 200) {
        final body = _dnResponseMap(response.data);
        throw Exception(
            '${body['message'] ?? 'Unable to save sender details.'}');
      }
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DnReviewPage(
            uuid: widget.uuid,
            dnTitle: widget.dnTitle,
            currentDn: widget.currentDn,
            currentBoxes: widget.currentBoxes,
            senderName:
                '${_sender?['name'] ?? _sender?['company_name'] ?? '-'}',
            receiverName:
                '${_receiver?['name'] ?? _receiver?['company_name'] ?? '-'}',
            deliveryDate: _deliveryDate.text.trim(),
            useSample: false,
            readOnly: false,
          ),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, changed ?? true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to save sender: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _senderValidationError() {
    if (_sender == null) return 'Sender is required.';
    if (_receiver == null) return 'To is required.';
    if (_senderAddress.text.trim().isEmpty)
      return 'Sender Address is required.';
    if (_receiverAddress.text.trim().isEmpty)
      return 'Delivery Address is required.';
    if (_usageValue == null) return 'Destination Usage is required.';
    if ('${_usageValue?['id'] ?? ''}' == 'other') {
      if (_customDestinationLocation.text.trim().isEmpty) {
        return 'Enter a destination location when Other is selected.';
      }
    } else if (_locationValue == null) {
      return 'Destination Location is required.';
    }
    if (_deliveryDate.text.trim().isEmpty) return 'Delivery Date is required.';
    return null;
  }

  Future<bool?> _confirmProceed() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue to Review?'),
        content: const Text(
          'Sender and delivery data will be saved. If this DN is still in Preparation, please make sure the address and instructions are correct before continuing to review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cek lagi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, continue'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDeliveryDate() async {
    if (widget.readOnly) return;
    final raw = _deliveryDate.text.trim();
    DateTime initialDate = DateTime.now();
    if (raw.isNotEmpty) {
      try {
        initialDate = DateTime.parse(raw);
      } catch (_) {
        initialDate = DateTime.now();
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final yyyy = picked.year.toString().padLeft(4, '0');
    final mm = picked.month.toString().padLeft(2, '0');
    final dd = picked.day.toString().padLeft(2, '0');
    _deliveryDate.text = '$yyyy-$mm-$dd';
    if (mounted) setState(() {});
  }

  bool get _isGeneralDn =>
      '${widget.currentDn['dan_number_department'] ?? ''}'.trim().isNotEmpty;

  String get _jobOrDepartmentLabel => _isGeneralDn ? 'Department' : 'Job No';

  String get _jobOrDepartmentValue {
    if (_isGeneralDn) {
      return '${widget.currentDn['dan_number_department'] ?? '-'}';
    }
    return '${widget.currentDn['job_number_text'] ?? widget.currentDn['job_number'] ?? '-'}';
  }

  String get _proformaNumberValue =>
      '${widget.currentDn['proforma_number'] ?? '-'}';

  List<Map<String, dynamic>> get _availableLocations {
    final usageId = '${_usageValue?['id'] ?? ''}';
    if (usageId.isEmpty || usageId == 'other') return const [];
    return _locations
        .where((row) => '${row['usageId'] ?? ''}' == usageId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Sender')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _apiUnavailable
              ? _ApiUnavailableState(message: _error!, onRetry: _load)
              : _error != null && !_manualAddressMode
                  ? _ErrorState(message: _error!, onRetry: _load)
                  : ListView(
                      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 88.h),
                      children: [
                        if (_manualAddressMode)
                          Container(
                            margin: EdgeInsets.only(bottom: 12.h),
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: AppColors.warningLight,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              _error ??
                                  'Sender master data has not been loaded from the server yet. The form can still be filled manually.',
                              style: TextStyle(
                                  fontSize: 12.sp, color: AppColors.warning),
                            ),
                          ),
                        _stepBanner('Sender', 'Review'),
                        SizedBox(height: 12.h),
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(12.w),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.local_shipping_outlined,
                                        color: AppColors.textSecondary,
                                        size: 22.r),
                                    SizedBox(width: 10.w),
                                    Text(
                                      'Delivery',
                                      style: TextStyle(
                                          fontSize: 18.sp,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10.h),
                                Divider(color: AppColors.border, height: 1),
                                SizedBox(height: 10.h),
                                _sectionBannerLabel('Sender Address :'),
                                SizedBox(height: 8.h),
                                _senderWebSection(),
                                SizedBox(height: 12.h),
                                Divider(color: AppColors.border, height: 1),
                                SizedBox(height: 10.h),
                                _sectionBannerLabel('Delivery Address :'),
                                SizedBox(height: 8.h),
                                _deliveryWebSection(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
      bottomNavigationBar: _loading ||
              _apiUnavailable ||
              (_error != null && !_manualAddressMode)
          ? null
          : SafeArea(
              minimum: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 10.h),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveAndNext,
                  icon: _saving
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2))
                      : Icon(widget.readOnly
                          ? Icons.visibility_outlined
                          : Icons.arrow_forward_rounded),
                  label:
                      Text(widget.readOnly ? 'View Review' : 'Save & Review'),
                ),
              ),
            ),
    );
  }

  Widget _stepBanner(String current, String next) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _stepNode('Sender', true),
          _stepLine(),
          _stepNode('Review', false),
        ],
      ),
    );
  }

  Widget _sectionBannerLabel(String text) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.infoLight,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _senderWebSection() {
    final senderItems = _senderOptions.isNotEmpty ? _senderOptions : _addresses;
    return Column(
      children: [
        _webFieldRow(
          'Sender',
          senderItems.isNotEmpty
              ? _dropdownField('Sender', _sender, _senderOptions, (value) {
                  setState(() {
                    _sender = value;
                    final isCustom = '${value?['id'] ?? ''}' == 'other';
                    _senderAddress.text =
                        isCustom ? '' : _addressTextFromRow(value);
                    _senderTelp.text =
                        isCustom ? '' : '${value?['telp'] ?? ''}';
                    _senderFax.text = isCustom ? '' : '${value?['fax'] ?? ''}';
                  });
                }, enabled: !widget.readOnly, itemsOverride: senderItems)
              : _readOnlyTextField('Sender data is not available'),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          '',
          TextField(
            enabled: !widget.readOnly,
            controller: _senderAddress,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '${_sender?['id'] ?? ''}' == 'other'
                  ? 'Custom Sender Address'
                  : 'Sender Address',
              alignLabelWithHint: true,
            ),
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Telp',
          TextField(
            enabled: !widget.readOnly,
            controller: _senderTelp,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Fax',
          TextField(
            enabled: !widget.readOnly,
            controller: _senderFax,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.print_outlined),
            ),
          ),
        ),
      ],
    );
  }

  Widget _deliveryWebSection() {
    final receiverItems =
        _receiverOptions.isNotEmpty ? _receiverOptions : _addresses;
    return Column(
      children: [
        _webFieldRow(
          'To',
          receiverItems.isNotEmpty
              ? _dropdownField('To', _receiver, _receiverOptions, (value) {
                  setState(() {
                    _receiver = value;
                    final isCustom = '${value?['id'] ?? ''}' == 'other';
                    _receiverAddress.text =
                        isCustom ? '' : _addressTextFromRow(value);
                    if (isCustom) {
                      _attn.clear();
                      _attnTelp.clear();
                    } else {
                      if (_attn.text.trim().isEmpty)
                        _attn.text = '${value?['attn'] ?? ''}';
                      if (_attnTelp.text.trim().isEmpty)
                        _attnTelp.text = '${value?['telp'] ?? ''}';
                    }
                  });
                }, enabled: !widget.readOnly, itemsOverride: receiverItems)
              : _readOnlyTextField('Receiver data is not available'),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Dan No',
          _readOnlyTextField(
              '${widget.currentDn['dan_number'] ?? widget.dnTitle}'),
        ),
        SizedBox(height: 12.h),
        _webFieldRow(
          '',
          TextField(
            enabled: !widget.readOnly,
            controller: _receiverAddress,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '${_receiver?['id'] ?? ''}' == 'other'
                  ? 'Custom Delivery Address'
                  : 'Delivery Address',
              alignLabelWithHint: true,
            ),
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          _jobOrDepartmentLabel,
          _readOnlyTextField(_jobOrDepartmentValue),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Cost Code',
          _readOnlyTextField('${widget.currentDn['cost_code_text'] ?? '-'}'),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Attn',
          TextField(
            enabled: !widget.readOnly,
            controller: _attn,
            decoration: const InputDecoration(),
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Telp',
          TextField(
            enabled: !widget.readOnly,
            controller: _attnTelp,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Special Instruction',
          TextField(
            enabled: !widget.readOnly,
            controller: _specialInstruction,
            maxLines: 3,
            decoration: const InputDecoration(),
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Destination Usage',
          _dropdownSimple(
            'Destination Usage',
            _usageValue,
            _usage,
            (value) => setState(() {
              _usageValue = value;
              _locationValue = null;
              if ('${value?['id'] ?? ''}' != 'other')
                _customDestinationLocation.clear();
            }),
            enabled: !widget.readOnly,
          ),
        ),
        SizedBox(height: 8.h),
        _webFieldRow(
          'Destination Location',
          '${_usageValue?['id'] ?? ''}' == 'other'
              ? TextField(
                  enabled: !widget.readOnly,
                  controller: _customDestinationLocation,
                  decoration:
                      const InputDecoration(hintText: 'Isi lokasi tujuan lain'),
                )
              : _dropdownSimple(
                  'Destination Location',
                  _locationValue,
                  _availableLocations,
                  (value) => setState(() => _locationValue = value),
                  enabled: !widget.readOnly,
                ),
        ),
        SizedBox(height: 12.h),
        _webFieldRow(
          'Delivery Date',
          TextField(
            controller: _deliveryDate,
            readOnly: true,
            onTap: _pickDeliveryDate,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
          ),
        ),
        SizedBox(height: 12.h),
        _webFieldRow(
          'Proforma No.',
          _readOnlyTextField(_proformaNumberValue),
        ),
        SizedBox(height: 12.h),
        _webFieldRow(
          'Proforma Name',
          _dropdownSimple(
            'Proforma Name',
            _proformaName,
            _proformaNames,
            (value) => setState(() => _proformaName = value),
            enabled: !widget.readOnly,
          ),
        ),
        SizedBox(height: 12.h),
        _webFieldRow(
          'Proforma Currency',
          _dropdownSimple(
            'Proforma Currency',
            _currency,
            _currencies,
            (value) => setState(() => _currency = value),
            enabled: !widget.readOnly,
          ),
        ),
        SizedBox(height: 12.h),
        _webFieldRow(
          'Sign Dispatched',
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _signDispatch,
                  onChanged: widget.readOnly
                      ? null
                      : (value) =>
                          setState(() => _signDispatch = value ?? false),
                ),
                Text(
                  _signDispatch ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: _signDispatch
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _webFieldRow(String label, Widget field) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 620;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: 6.h),
                  child: Text(
                    label,
                    style: TextStyle(
                        fontSize: 13.sp, color: AppColors.textSecondary),
                  ),
                ),
              field,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120.w,
              child: Padding(
                padding: EdgeInsets.only(top: 14.h),
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: 13.sp, color: AppColors.textSecondary),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(child: field),
          ],
        );
      },
    );
  }

  Widget _readOnlyTextField(String value) {
    return InputDecorator(
      decoration: const InputDecoration(),
      child: Text(
        value.isEmpty ? '-' : value,
        style: TextStyle(
          fontSize: 14.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _readOnlyTileCompact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.sp,
          ),
        ),
        SizedBox(height: 4.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            value.isEmpty ? '-' : value,
            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _stepNode(String text, bool active) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 28.w,
            height: 28.w,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(999.r),
            ),
            child: Icon(
              active ? Icons.check_rounded : Icons.circle_outlined,
              size: 16.r,
              color: active ? Colors.white : AppColors.textTertiary,
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: active ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepLine() {
    return Container(
      width: 24.w,
      height: 2.h,
      margin: EdgeInsets.symmetric(horizontal: 6.w),
      color: AppColors.border,
    );
  }

  Widget _dropdownField(
    String label,
    Map<String, dynamic>? value,
    List<Map<String, dynamic>> items,
    ValueChanged<Map<String, dynamic>?> onChanged, {
    bool enabled = true,
    List<Map<String, dynamic>>? itemsOverride,
  }) {
    final sourceItems = itemsOverride ?? items;
    Map<String, dynamic>? currentValue;
    if (value != null) {
      for (final item in sourceItems) {
        if ('${item['id'] ?? ''}' == '${value['id'] ?? ''}') {
          currentValue = item;
          break;
        }
      }
    }
    return DropdownButtonFormField<Map<String, dynamic>>(
      value: currentValue,
      isExpanded: true,
      onChanged: enabled ? onChanged : null,
      decoration: const InputDecoration(),
      items: sourceItems
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(
                  '${e['company_name'] ?? e['name'] ?? e['label'] ?? '-'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      selectedItemBuilder: (context) => sourceItems
          .map(
            (e) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${e['company_name'] ?? e['name'] ?? e['label'] ?? '-'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _dropdownSimple(
    String label,
    Map<String, dynamic>? value,
    List<Map<String, dynamic>> items,
    ValueChanged<Map<String, dynamic>?> onChanged, {
    bool enabled = true,
  }) {
    return DropdownButtonFormField<Map<String, dynamic>>(
      value: value,
      isExpanded: true,
      onChanged: enabled ? onChanged : null,
      decoration: const InputDecoration(),
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(
                  '${e['name'] ?? e['inventory_usage'] ?? e['inventory_location'] ?? e['proforma_name'] ?? e['inventory_currency_initial'] ?? '-'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      selectedItemBuilder: (context) => items
          .map(
            (e) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${e['name'] ?? e['inventory_usage'] ?? e['inventory_location'] ?? e['proforma_name'] ?? e['inventory_currency_initial'] ?? '-'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}

class DnReviewPage extends StatefulWidget {
  final String uuid;
  final String dnTitle;
  final Map<String, dynamic> currentDn;
  final List<Map<String, dynamic>> currentBoxes;
  final String senderName;
  final String receiverName;
  final String deliveryDate;
  final bool useSample;
  final bool readOnly;

  const DnReviewPage({
    Key? key,
    required this.uuid,
    required this.dnTitle,
    required this.currentDn,
    required this.currentBoxes,
    required this.senderName,
    required this.receiverName,
    required this.deliveryDate,
    required this.useSample,
    required this.readOnly,
  }) : super(key: key);

  @override
  State<DnReviewPage> createState() => _DnReviewPageState();
}

class _DnReviewPageState extends State<DnReviewPage> {
  late final Dio _dio;
  bool _loading = true;
  bool _finishing = false;
  bool _downloading = false;
  Map<String, dynamic> _dn = const {};
  List<Map<String, dynamic>> _boxes = const [];
  Map<String, dynamic> _meta = const {};

  @override
  void initState() {
    super.initState();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    _load();
  }

  Future<void> _setAuth() async {
    await _setDnAuthHeaders(_dio);
  }

  Future<void> _load() async {
    if (widget.useSample) {
      setState(() {
        _dn = widget.currentDn;
        _boxes = _normalizeDnBoxes(widget.currentBoxes);
        _loading = false;
      });
      return;
    }

    try {
      await _setAuth();
      // Sama dengan halaman Preview: endpoint web baru mengirim header, box,
      // dan item sebagai tiga daftar yang terpisah.
      final response = await _dio
          .get('/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}');
      final body = _dnResponseMap(response.data);
      final payload = body['data'];
      if (response.statusCode != 200 ||
          payload is! Map ||
          payload['header'] is! Map) {
        throw Exception('${body['message'] ?? 'Unable to load review data.'}');
      }
      final data = Map<String, dynamic>.from(payload);
      final header = Map<String, dynamic>.from(payload['header'] as Map);
      final mergedBoxes = await _mergeDnBoxesWithCache(
        widget.uuid,
        _attachDnItemsToBoxes(
          data['boxes'] as List? ?? const [],
          data['items'] as List? ?? const [],
        ),
      );
      Map<String, List<int>> photoIds = const {};
      try {
        photoIds = await _loadDnItemPhotoIds(_dio, widget.uuid);
      } catch (_) {
        // Endpoint foto optional untuk kompatibilitas data DN lama.
      }
      setState(() {
        _dn = {
          ...header,
          'dan_number': '${header['dan_number'] ?? ''}'.trim().isEmpty
              ? 'Assigned on finish'
              : header['dan_number'],
          'status_text':
              header['statusLabel'] ?? header['status'] ?? 'Preparation',
          'job_number_text':
              header['jobNumberLabel'] ?? header['dan_number_code'] ?? '-',
          'cost_code_text': header['cost_code'] ?? '-',
          'usage_text': header['usageName'] ?? '-',
          'location_text': header['locationName'] ?? '-',
          'sender_address_text':
              header['senderSummary'] ?? header['sender_address'] ?? '',
          'delivery_address_text':
              header['deliverySummary'] ?? header['delivery_address'] ?? '',
          'dispatch_by_name':
              header['dispatchedByName'] ?? header['created_user'] ?? '-',
        };
        _boxes = _attachDnPhotoIds(mergedBoxes, photoIds);
        _meta = {'total_box': mergedBoxes.length};
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _dn = widget.currentDn;
        _boxes = _normalizeDnBoxes(widget.currentBoxes);
        _meta = const {};
        _loading = false;
      });
    }
  }

  Future<Directory> _resolveDownloadDirectory() async {
    if (Platform.isAndroid) {
      final publicDownloadDir =
          Directory('/storage/emulated/0/Download/SeascapeDN');
      try {
        var storageStatus = await Permission.storage.request();
        if (!(storageStatus.isGranted ||
            storageStatus.isLimited ||
            storageStatus.isProvisional)) {
          final manageStatus = await Permission.manageExternalStorage.request();
          if (!(manageStatus.isGranted ||
              manageStatus.isLimited ||
              manageStatus.isProvisional)) {
            throw Exception(
                'Permission to access the Download folder has not been granted.');
          }
        }

        if (!await publicDownloadDir.exists()) {
          await publicDownloadDir.create(recursive: true);
        }
        return publicDownloadDir;
      } catch (e) {
        throw Exception(
          'The file could not be saved to the phone Download folder. '
          'Please check storage permission and try again. Detail: $e',
        );
      }
    }
    return getApplicationDocumentsDirectory();
  }

  String _webDownloadPageForKind(String kind) {
    switch (kind) {
      case 'dan-form':
        return 'form';
      case 'dan-label':
        return 'label';
      case 'dan-proforma':
        return 'proforma';
      default:
        return 'form';
    }
  }

  List<String> _webDownloadPathsForKind(String kind) {
    switch (kind) {
      case 'dan-form':
        return [
          '/delivery-not-out-going/print/dan-form/${Uri.encodeComponent(widget.uuid)}',
          '/delivery-not-out-going/download/dan-form/${Uri.encodeComponent(widget.uuid)}',
        ];
      case 'dan-label':
        return [
          '/delivery-not-out-going/download/dan-label/${Uri.encodeComponent(widget.uuid)}',
        ];
      case 'dan-proforma':
        return [
          '/delivery-not-out-going/print/dan-proforma/${Uri.encodeComponent(widget.uuid)}',
        ];
      default:
        return [
          '/api/dn/download/$kind/${Uri.encodeComponent(widget.uuid)}',
        ];
    }
  }

  Future<String?> _resolveWebSessionCookie() async {
    return AppAuthSession.getStoredWebSessionCookie();
  }

  Future<void> _prepareWebDownloadAccess(
      String page, String cookieHeader) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json, text/plain, */*',
          'Content-Type': Headers.formUrlEncodedContentType,
          'Cookie': cookieHeader,
        },
      ),
    );

    final response = await dio.post(
      '/dan/api/data',
      data: {
        'mod': 'set-access-download',
        'id': widget.uuid,
        'page': page,
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final raw = '${response.data ?? ''}'.trim().toLowerCase();
    if (response.statusCode == null ||
        response.statusCode! >= 400 ||
        !(raw == 'true' || raw == '1')) {
      throw Exception(
          'Web download access has not been opened for this document yet.');
    }
  }

  Future<void> _downloadPdf(String kind, String fallbackName) async {
    if (widget.useSample) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sample mode cannot download documents yet.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _downloading = true);
    try {
      final directory = await _resolveDownloadDirectory();
      final fileName = fallbackName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final filePath = '${directory.path}${Platform.pathSeparator}$fileName';
      // PDF selalu dibuat oleh backend DN web agar layout DAN dan label persis
      // sama. Aplikasi hanya mengunduh hasil PDF tersebut.
      await _setAuth();
      final response = await _dio.download(
        '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/print/$kind',
        filePath,
        options: Options(
          headers: const {'Accept': 'application/pdf'},
          responseType: ResponseType.bytes,
        ),
      );
      if (response.statusCode != 200) {
        final raw = response.data is List<int>
            ? utf8.decode(response.data as List<int>, allowMalformed: true)
            : '${response.data ?? ''}';
        final serverMessage = _dnResponseMap(raw)['message'];
        throw Exception(
            '${serverMessage ?? 'Server belum dapat membuat dokumen $kind.'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved to $filePath'),
          backgroundColor: AppColors.success,
          action: SnackBarAction(
            label: 'Open',
            textColor: Colors.white,
            onPressed: () async {
              await OpenFilex.open(filePath);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download document: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _copyShareLink() async {
    final downloadUrls =
        Map<String, dynamic>.from(_meta['download_urls'] ?? const {});
    final link = '${downloadUrls['dan_form'] ?? ''}'.trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The DAN link is not available yet.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Link DAN disalin. Bisa dipakai untuk share manual/email.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _finish(BuildContext context) async {
    final isPreparation =
        '${_dn['status_text'] ?? widget.currentDn['status_text'] ?? ''}'
                .toLowerCase() ==
            'preparation';
    if (isPreparation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Finish Dispatch?'),
          content: const Text(
            'Status DN masih Preparation. Setelah finish, data akan diproses ke tahap dispatch. Pastikan sender, alamat, box, dan item sudah benar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cek lagi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ya, finish'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (widget.useSample) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sample mode: finish was not sent to the server.')),
      );
      Navigator.pop(context, true);
      return;
    }

    setState(() => _finishing = true);
    try {
      await _setAuth();
      // Endpoint web baru baru mengalokasikan nomor DAN final pada aksi ini.
      // Sebelum titik ini record tetap Draft/Preparation.
      final response = await _dio.post(
          '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/mark-sent');
      if (response.statusCode != 200) {
        final body = _dnResponseMap(response.data);
        throw Exception('${body['message'] ?? 'Unable to finish dispatch.'}');
      }
      if (context.mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to finish dispatch: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  bool _hasReviewName(String value) {
    final clean = value.trim();
    return clean.isNotEmpty && clean != '-';
  }

  String _companyFromSummary(String summary) {
    final firstLine = summary
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return '';
    // Endpoint web selalu menyusun summary sebagai: nama perusahaan lalu alamat.
    // Jangan pakai daftar awalan "PT/CV" saja karena nama seperti
    // "Ashtead Technology (SEA)" juga merupakan nama perusahaan.
    final normalized = firstLine.toLowerCase();
    final looksLikeAddress = normalized.startsWith('jl ') ||
        normalized.startsWith('jl.') ||
        normalized.startsWith('jalan ') ||
        normalized.startsWith('rt ') ||
        normalized.startsWith('no.') ||
        RegExp(r'^\d').hasMatch(normalized);
    return looksLikeAddress ? '' : firstLine;
  }

  String _reviewAddressOnly(String summary, String company) {
    final companyKey = company.trim().toLowerCase();
    final lines = summary
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) {
      final normalized = line.toLowerCase();
      // Telepon, fax, dan attn sudah memiliki kolom sendiri di Review.
      return !normalized.startsWith('tel :') &&
          !normalized.startsWith('tel:') &&
          !normalized.startsWith('fax :') &&
          !normalized.startsWith('fax:') &&
          !normalized.startsWith('attn :') &&
          !normalized.startsWith('attn:');
    }).toList();
    if (companyKey.isNotEmpty &&
        lines.isNotEmpty &&
        lines.first.toLowerCase() == companyKey) {
      lines.removeAt(0);
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final qrUrl = _dnQrImageUrl(
      '${_dn['uuid'] ?? widget.uuid}',
      explicitUrl: '${_meta['dn_qr_url'] ?? ''}',
    );
    final totalBoxes = _meta['total_box'] ?? _boxes.length;
    final totalWeight = '${_meta['total_weight'] ?? ''}'.trim();
    final senderSummary = '${_dn['sender_address_text'] ?? ''}'.trim();
    final receiverSummary = '${_dn['delivery_address_text'] ?? ''}'.trim();
    final configuredSenderName =
        '${_dn['sender_name'] ?? widget.senderName}'.trim();
    final configuredReceiverName =
        '${_dn['receiver_name'] ?? widget.receiverName}'.trim();
    final senderName = _hasReviewName(configuredSenderName)
        ? configuredSenderName
        : _companyFromSummary(senderSummary);
    final receiverName = _hasReviewName(configuredReceiverName)
        ? configuredReceiverName
        : _companyFromSummary(receiverSummary);
    final senderAddress = _reviewAddressOnly(senderSummary, senderName);
    final receiverAddress = _reviewAddressOnly(receiverSummary, receiverName);
    final senderTel = _firstNonEmptyValue(_dn, ['sender_tel', 'sender_telp']);
    final senderFax = _firstNonEmptyValue(_dn, ['sender_fax']);
    final statusText =
        '${_dn['status_text'] ?? widget.currentDn['status_text'] ?? '-'}';
    final proformaNumber = '${_dn['proforma_number'] ?? '-'}';
    final jobOrDept =
        '${_dn['job_number_text'] ?? _dn['department_text'] ?? '-'}';
    final costCode = '${_dn['cost_code_text'] ?? '-'}';
    final usageText = '${_dn['usage_text'] ?? '-'}';
    final locationText = '${_dn['location_text'] ?? '-'}';
    final attnText = '${_dn['attn'] ?? '-'}';
    final attnTelText = _firstNonEmptyValue(
        _dn, ['attn_telp', 'receiver_tel', 'receiver_telp']);
    final dispatchBy = '${_dn['dispatch_by_name'] ?? '-'}';
    final signedText = (_dn['sign_dispatch'] == 1) ? 'Signed' : 'Not Signed';
    final canDownloadDocuments =
        ['sent', 'received'].contains(statusText.toLowerCase().trim());
    final deliveryDateText =
        '${_dn['delivery_date'] ?? widget.deliveryDate}'.trim().isEmpty
            ? '-'
            : '${_dn['delivery_date'] ?? widget.deliveryDate}';

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Review')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                Container(
                  padding: EdgeInsets.all(18.w),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16.r),
                    border:
                        Border.all(color: AppColors.border.withOpacity(0.7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Delivery Note Review',
                              style: TextStyle(
                                  fontSize: 18.sp, fontWeight: FontWeight.w800),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10.w, vertical: 6.h),
                            decoration: BoxDecoration(
                              color: _statusChipBg(statusText),
                              borderRadius: BorderRadius.circular(999.r),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w800,
                                color: _statusChipFg(statusText),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 92.w,
                            height: 92.w,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: qrUrl.isEmpty
                                ? Icon(Icons.qr_code_2_rounded,
                                    size: 50.r, color: AppColors.textTertiary)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(14.r),
                                    child: Image.network(
                                      qrUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.qr_code_2_rounded,
                                        size: 50.r,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                          ),
                          SizedBox(width: 14.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ReviewField(
                                  label: 'DN Number',
                                  value:
                                      '${_dn['dan_number'] ?? widget.dnTitle}',
                                ),
                                SizedBox(height: 10.h),
                                _ReviewField(
                                    label: 'Proforma No',
                                    value: proformaNumber),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16.h),
                      Divider(
                          height: 1, color: AppColors.border.withOpacity(0.8)),
                      SizedBox(height: 14.h),
                      Row(
                        children: [
                          Expanded(
                              child: _ReviewMetricTile(
                                  label: 'Job / Department', value: jobOrDept)),
                          SizedBox(width: 10.w),
                          Expanded(
                              child: _ReviewMetricTile(
                                  label: 'Cost Code', value: costCode)),
                        ],
                      ),
                      SizedBox(height: 12.h),
                      Wrap(
                        spacing: 8.w,
                        runSpacing: 8.h,
                        children: [
                          _reviewChip('Total Box: $totalBoxes'),
                          if (totalWeight.isNotEmpty)
                            _reviewChip('Total Weight: $totalWeight Kg'),
                          _reviewChip('Dispatch: $signedText'),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
                _reviewSectionCard(
                  title: 'Sender',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReviewField(label: 'Name', value: senderName),
                      SizedBox(height: 10.h),
                      _ReviewField(
                          label: 'Address',
                          value: senderAddress.isEmpty ? '-' : senderAddress),
                      if (senderTel.trim().isNotEmpty &&
                          senderTel.trim() != '-') ...[
                        SizedBox(height: 10.h),
                        _ReviewField(label: 'No Telp', value: senderTel),
                      ],
                      if (senderFax.trim().isNotEmpty &&
                          senderFax.trim() != '-') ...[
                        SizedBox(height: 10.h),
                        _ReviewField(label: 'Fax', value: senderFax),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                _reviewSectionCard(
                  title: 'Delivery',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReviewField(label: 'Name', value: receiverName),
                      SizedBox(height: 10.h),
                      _ReviewField(
                          label: 'Address',
                          value:
                              receiverAddress.isEmpty ? '-' : receiverAddress),
                      if (attnText.trim().isNotEmpty &&
                          attnText.trim() != '-') ...[
                        SizedBox(height: 10.h),
                        _ReviewField(label: 'Attn', value: attnText),
                      ],
                      if (attnTelText.trim().isNotEmpty &&
                          attnTelText.trim() != '-') ...[
                        SizedBox(height: 10.h),
                        _ReviewField(label: 'Phone', value: attnTelText),
                      ],
                      SizedBox(height: 10.h),
                      _ReviewField(
                          label: 'Delivery Date', value: deliveryDateText),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),
                _reviewSectionCard(
                  title: 'Dispatch Summary',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ReviewField(label: 'Usage', value: usageText),
                      SizedBox(height: 10.h),
                      _ReviewField(label: 'Location', value: locationText),
                      SizedBox(height: 10.h),
                      _ReviewField(label: 'Attn', value: attnText),
                      SizedBox(height: 10.h),
                      _ReviewField(label: 'Dispatch By', value: dispatchBy),
                    ],
                  ),
                ),
                if (canDownloadDocuments) ...[
                  SizedBox(height: 16.h),
                  Text('Documents',
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w800)),
                  SizedBox(height: 10.h),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10.h,
                    crossAxisSpacing: 10.w,
                    childAspectRatio: 2.4,
                    children: [
                      _actionCard(
                        icon: Icons.picture_as_pdf_outlined,
                        label: 'Download DAN',
                        color: const Color(0xFFFF5E72),
                        onTap: _downloading
                            ? null
                            : () => _downloadPdf(
                                  'dan-form',
                                  '${_dn['dan_number'] ?? widget.dnTitle}.pdf',
                                ),
                      ),
                      _actionCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'Download Label',
                        color: const Color(0xFF2D9CDB),
                        onTap: _downloading
                            ? null
                            : () => _downloadPdf(
                                  'dan-label',
                                  '${_dn['dan_number'] ?? widget.dnTitle}-Label.pdf',
                                ),
                      ),
                      _actionCard(
                        icon: Icons.request_quote_outlined,
                        label: 'Download Proforma',
                        color: const Color(0xFF34C38F),
                        onTap: _downloading
                            ? null
                            : () => _downloadPdf(
                                  'dan-proforma',
                                  '$proformaNumber.pdf',
                                ),
                      ),
                      _actionCard(
                        icon: Icons.mail_outline_rounded,
                        label: 'Share DAN',
                        color: const Color(0xFFFF9F43),
                        onTap: _copyShareLink,
                      ),
                    ],
                  ),
                  SizedBox(height: 18.h),
                ],
                Text('Equipments List',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w800)),
                SizedBox(height: 10.h),
                if (_boxes.isEmpty)
                  const _EmptyBox()
                else
                  ..._boxes.map((box) {
                    final items = (box['items'] as List? ?? const [])
                        .whereType<Map>()
                        .map((e) => Map<String, dynamic>.from(e))
                        .toList();
                    return Card(
                      margin: EdgeInsets.only(bottom: 12.h),
                      child: Padding(
                        padding: EdgeInsets.all(14.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('BOX${box['box_number']}',
                                style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 10.h),
                            Wrap(
                              spacing: 8.w,
                              runSpacing: 8.h,
                              children: [
                                _reviewChip(
                                    'Label: ${'${box['box_label'] ?? ''}'.trim().isEmpty ? '-' : box['box_label']}'),
                                _reviewChip(
                                    'DIM: ${'${box['box_dim'] ?? ''}'.trim().isEmpty ? '-' : box['box_dim']}'),
                                _reviewChip(
                                    'Weight: ${box['box_weight'] ?? '0'} kg'),
                                _reviewChip('Item: ${items.length}'),
                              ],
                            ),
                            SizedBox(height: 12.h),
                            if (items.isEmpty)
                              const Text('No items yet')
                            else
                              ...items.map((item) {
                                final name = _equipmentDisplayName(item);
                                final sn =
                                    '${item['equipment_sn'] ?? item['sn'] ?? '-'}';
                                return Padding(
                                  padding: EdgeInsets.only(bottom: 8.h),
                                  child: Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(12.w),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceVariant,
                                      borderRadius: BorderRadius.circular(10.r),
                                    ),
                                    child: Row(
                                      children: [
                                        _DnItemPhotoButton(
                                          dio: _dio,
                                          uuid: widget.uuid,
                                          item: item,
                                          readOnly: true,
                                          onChanged: _load,
                                        ),
                                        SizedBox(width: 8.w),
                                        Expanded(
                                          child: Text(
                                            '$name\nSN: $sn | Qty: ${item['equipment_qty'] ?? 1}',
                                            style: TextStyle(
                                                fontSize: 13.sp,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                          ],
                        ),
                      ),
                    );
                  }),
                SizedBox(height: 20.h),
                if (widget.readOnly)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final changed = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DnDetailPage(
                            uuid: widget.uuid,
                            title: '${_dn['dan_number'] ?? widget.dnTitle}',
                            forceProcessView: true,
                          ),
                        ),
                      );
                      if (changed == true && mounted) {
                        _load();
                      }
                    },
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview DN Process'),
                  ),
                if (widget.readOnly) SizedBox(height: 12.h),
                if (!widget.readOnly)
                  ElevatedButton.icon(
                    onPressed: _finishing ? null : () => _finish(context),
                    icon: _finishing
                        ? SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child:
                                const CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.local_shipping_outlined),
                    label: const Text('Finish Dispatch'),
                  ),
              ],
            ),
    );
  }

  Widget _reviewChip(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _reviewSectionCard({required String title, required Widget child}) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14.r),
      child: Ink(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: color.withOpacity(onTap == null ? 0.08 : 0.14),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18.r),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusChipBg(String status) {
    switch (status.toLowerCase()) {
      case 'sent':
        return const Color(0xFFFFF3D8);
      case 'received':
        return const Color(0xFFE7FFF2);
      default:
        return const Color(0xFFF1EEFF);
    }
  }

  Color _statusChipFg(String status) {
    switch (status.toLowerCase()) {
      case 'sent':
        return const Color(0xFFC78B00);
      case 'received':
        return const Color(0xFF199E63);
      default:
        return AppColors.primary;
    }
  }
}

class _ReviewField extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewField({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 5.h),
        Text(
          value.trim().isEmpty ? '-' : value,
          textAlign: TextAlign.left,
          style: TextStyle(
            fontSize: 15.sp,
            fontWeight: FontWeight.w700,
            height: 1.35,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ReviewMetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewMetricTile({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            value.trim().isEmpty ? '-' : value,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DnItemPhotoPicker extends StatelessWidget {
  final List<XFile> photos;
  final bool enabled;
  final ValueChanged<List<XFile>> onChanged;
  final VoidCallback? onScan;

  const _DnItemPhotoPicker({
    required this.photos,
    required this.enabled,
    required this.onChanged,
    this.onScan,
  });

  Future<void> _pick(BuildContext context) async {
    if (photos.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A maximum of 5 photos is allowed for each item.')),
      );
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 72,
      maxWidth: 1600,
    );
    if (image != null) onChanged([...photos, image]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Item Photo (Optional)',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 8.w,
          runSpacing: 8.h,
          children: [
            ...photos.asMap().entries.map((entry) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8.r),
                      child: Image.file(
                        File(entry.value.path),
                        width: 70.w,
                        height: 70.w,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (enabled)
                      Positioned(
                        right: -7.w,
                        top: -7.h,
                        child: InkWell(
                          onTap: () => onChanged([
                            for (var i = 0; i < photos.length; i++)
                              if (i != entry.key) photos[i],
                          ]),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: AppColors.error,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                )),
            if (enabled && photos.length < 5)
              OutlinedButton.icon(
                onPressed: () => _pick(context),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add Photo'),
              ),
            if (enabled && onScan != null)
              OutlinedButton.icon(
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('Scan QR'),
              ),
          ],
        ),
        SizedBox(height: 4.h),
        Text('Maximum 5 photos, 2 MB each.',
            style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _DnItemPhotoButton extends StatefulWidget {
  final Dio dio;
  final String uuid;
  final Map<String, dynamic> item;
  final bool readOnly;
  final VoidCallback onChanged;

  const _DnItemPhotoButton({
    required this.dio,
    required this.uuid,
    required this.item,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<_DnItemPhotoButton> createState() => _DnItemPhotoButtonState();
}

class _DnItemPhotoButtonState extends State<_DnItemPhotoButton> {
  List<int> get _photoIds => (widget.item['photo_ids'] as List? ?? const [])
      .map((value) => int.tryParse('$value'))
      .whereType<int>()
      .toList();

  Future<Uint8List?> _photoBytes(int id) async {
    final response = await widget.dio.get<List<int>>(
      '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/item-photos/$id',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.statusCode == 200 && response.data != null
        ? Uint8List.fromList(response.data!)
        : null;
  }

  Future<void> _addPhoto(BuildContext context) async {
    if (widget.readOnly) return;
    if (_photoIds.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A maximum of 5 photos is allowed for each item.')));
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final file = await ImagePicker()
        .pickImage(source: source, imageQuality: 72, maxWidth: 1600);
    final itemId = int.tryParse('${widget.item['id'] ?? ''}');
    if (file == null || itemId == null) return;
    try {
      await _uploadDnItemPhotos(widget.dio,
          uuid: widget.uuid, itemId: itemId, photos: [file]);
      if (!mounted) return;
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Item photo saved successfully.'),
          backgroundColor: AppColors.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to save photo: $e'),
          backgroundColor: AppColors.error));
    }
  }

  Future<void> _deletePhoto(BuildContext context, int photoId) async {
    try {
      final response = await widget.dio.delete(
          '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/item-photos/$photoId');
      if (response.statusCode != 200)
        throw Exception(_dnResponseMap(response.data)['message'] ??
            'Unable to delete photo.');
      if (!mounted) return;
      widget.onChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Unable to delete photo: $e'),
          backgroundColor: AppColors.error));
    }
  }

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 20.h),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Item Photos',
                    style: TextStyle(
                        fontSize: 18.sp, fontWeight: FontWeight.w800)),
                SizedBox(height: 12.h),
                if (_photoIds.isEmpty)
                  Text('No photos yet.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13.sp))
                else
                  Wrap(
                    spacing: 10.w,
                    runSpacing: 10.h,
                    children: _photoIds
                        .map((id) => Stack(children: [
                              FutureBuilder<Uint8List?>(
                                future: _photoBytes(id),
                                builder: (context, snapshot) => Container(
                                  width: 110.w,
                                  height: 110.w,
                                  decoration: BoxDecoration(
                                      color: AppColors.surfaceVariant,
                                      borderRadius:
                                          BorderRadius.circular(10.r)),
                                  child: snapshot.data == null
                                      ? const Center(
                                          child: Icon(Icons.photo_outlined))
                                      : ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10.r),
                                          child: Image.memory(snapshot.data!,
                                              fit: BoxFit.cover)),
                                ),
                              ),
                              if (!widget.readOnly)
                                Positioned(
                                  right: 2.w,
                                  top: 2.h,
                                  child: IconButton(
                                    tooltip: 'Delete photo',
                                    style: IconButton.styleFrom(
                                        backgroundColor: Colors.white),
                                    icon: const Icon(Icons.delete_outline,
                                        color: AppColors.error),
                                    onPressed: () =>
                                        _deletePhoto(sheetContext, id),
                                  ),
                                ),
                            ]))
                        .toList(),
                  ),
                if (!widget.readOnly) ...[
                  SizedBox(height: 16.h),
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                          onPressed: () => _addPhoto(sheetContext),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(_photoIds.isEmpty
                              ? 'Add Photo'
                              : 'Replace / Add Photo'))),
                ],
              ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoIds.isNotEmpty;
    if (!hasPhoto) {
      return IconButton(
        tooltip: 'Add photo',
        onPressed: _openSheet,
        icon: const Icon(Icons.add_a_photo_outlined,
            color: AppColors.textSecondary),
      );
    }
    return InkWell(
      onTap: _openSheet,
      borderRadius: BorderRadius.circular(8.r),
      child: FutureBuilder<Uint8List?>(
        future: _photoBytes(_photoIds.first),
        builder: (context, snapshot) => ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Container(
            width: 42.w,
            height: 42.w,
            color: AppColors.surfaceVariant,
            child: snapshot.data == null
                ? const Icon(Icons.photo_outlined, color: AppColors.primary)
                : Image.memory(snapshot.data!, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

class DnEquipmentPage extends StatefulWidget {
  final String uuid;
  final Map<String, dynamic> box;
  final Dio dio;
  final bool useSample;
  final bool readOnly;

  const DnEquipmentPage({
    Key? key,
    required this.uuid,
    required this.box,
    required this.dio,
    required this.useSample,
    required this.readOnly,
  }) : super(key: key);

  @override
  State<DnEquipmentPage> createState() => _DnEquipmentPageState();
}

class _DnEquipmentPageState extends State<DnEquipmentPage> {
  final _searchController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _valueController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic>? _selectedItem;
  String? _lastScannedText;
  List<XFile> _photos = const [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _qtyController.dispose();
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadInventory() async {
    setState(() => _loading = true);
    try {
      if (widget.useSample) {
        setState(() {
          _items = const [
            {
              'id': 'sample-1',
              'asset_code': 'AST-SSI-0001',
              'group': 'ROV',
              'brand': 'Seascape',
              'model': 'ST Coupler Netviel',
              'sn': 'SN-SAMPLE-001',
              'status_code': 2,
            },
            {
              'id': 'sample-2',
              'asset_code': 'AST-SSI-0002',
              'group': 'Survey',
              'brand': 'SSI',
              'model': 'Sample Beacon',
              'sn': 'SN-SAMPLE-002',
              'status_code': 2,
            },
          ];
          _loading = false;
        });
        return;
      }

      final response = await widget.dio
          .get('/api/delivery-notes/inventory', queryParameters: {
        'search': _searchController.text.trim(),
      });
      final body = _dnResponseMap(response.data);
      final rows = (body['data'] as List? ?? const []).map((e) {
        final row = Map<String, dynamic>.from(e as Map);
        return {
          ...row,
          'asset_code': row['assetCode'],
          'sn': row['serialNumber'],
          'inventory_group': row['name'],
          'inventory_model': row['model'],
        };
      }).toList();
      final query =
          (_lastScannedText ?? _searchController.text).trim().toLowerCase();
      Map<String, dynamic>? matched;
      if (query.isNotEmpty) {
        for (final row in rows) {
          final assetCode = '${row['asset_code'] ?? ''}'.trim().toLowerCase();
          final serial =
              '${row['sn'] ?? row['equipment_sn'] ?? ''}'.trim().toLowerCase();
          if (assetCode == query || serial == query) {
            matched = row;
            break;
          }
        }
        matched ??= rows.cast<Map<String, dynamic>?>().firstWhere(
          (row) {
            if (row == null) return false;
            final assetCode = '${row['asset_code'] ?? ''}'.trim().toLowerCase();
            final serial = '${row['sn'] ?? row['equipment_sn'] ?? ''}'
                .trim()
                .toLowerCase();
            return assetCode.contains(query) || serial.contains(query);
          },
          orElse: () => null,
        );
      }
      setState(() {
        _items = rows;
        // Jangan biarkan pilihan lama ikut tersimpan saat hasil scan/pencarian
        // baru tidak menemukan asset yang sesuai.
        _selectedItem = matched ?? (query.isEmpty ? _selectedItem : null);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to load equipment: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _openScanPage() async {
    final rawCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const DnEquipmentScanPage()),
    );
    if (rawCode == null || rawCode.trim().isEmpty || !mounted) return;

    final parsed = QrScanResult.fromRawData(rawCode);
    final scannedCode = parsed.assetCode.isNotEmpty
        ? parsed.assetCode
        : parsed.sn.isNotEmpty
            ? parsed.sn
            : rawCode.trim();
    _lastScannedText = scannedCode;
    _searchController.text = scannedCode;
    setState(() => _selectedItem = null);
    await _loadInventory();
    if (!mounted) return;

    final selected = _selectedItem;
    final exactMatch = selected != null &&
        ('${selected['asset_code'] ?? ''}'.trim().toLowerCase() ==
                scannedCode.toLowerCase() ||
            '${selected['sn'] ?? selected['equipment_sn'] ?? ''}'
                    .trim()
                    .toLowerCase() ==
                scannedCode.toLowerCase());
    if (exactMatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Asset found and selected.'),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    final addOther = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Data Not Found'),
        content: Text(
          'The code "$scannedCode" is not registered in inventory. '
          'Add it as an Other Item?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, add item'),
          ),
        ],
      ),
    );
    if (addOther != true || !mounted) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DnOtherItemPage(
          uuid: widget.uuid,
          box: widget.box,
          dio: widget.dio,
          useSample: widget.useSample,
          readOnly: widget.readOnly,
          initialSerial: scannedCode,
        ),
      ),
    );
    if (changed == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _save() async {
    if (_selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select an equipment item first.'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final newItem = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'equipment_name': _displayName(_selectedItem!),
        'asset_code': '${_selectedItem!['asset_code'] ?? '-'}',
        'inventory_model':
            '${_selectedItem!['inventory_model'] ?? _selectedItem!['model'] ?? ''}',
        'inventory_group':
            '${_selectedItem!['inventory_group'] ?? _selectedItem!['group'] ?? ''}',
        'equipment_sn': '${_selectedItem!['sn'] ?? '-'}',
        'equipment_qty': _qtyController.text.trim().isEmpty
            ? '1'
            : _qtyController.text.trim(),
        'equipment_value': _valueController.text.trim().isEmpty
            ? '0'
            : _valueController.text.trim(),
      };

      if (widget.useSample) {
        final items =
            (widget.box['items'] as List? ?? <Map<String, dynamic>>[]);
        items.add(newItem);
        widget.box['items'] = items;
        await _rememberDnBoxItems(
          widget.uuid,
          widget.box['box_number'],
          items
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final response = await widget.dio.post(
          '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/items/inventory',
          data: {
            'inventoryId': _selectedItem!['id'],
            'boxNumber': widget.box['box_number'],
            'quantity': _qtyController.text.trim().isEmpty
                ? 1
                : _qtyController.text.trim(),
            'value': _valueController.text.trim().isEmpty
                ? 0
                : _valueController.text.trim(),
            'notes': _notesController.text.trim(),
          });
      if (response.statusCode != 201) {
        final body = _dnResponseMap(response.data);
        throw Exception('${body['message'] ?? 'Unable to add the item.'}');
      }

      String? photoWarning;
      if (_photos.isNotEmpty) {
        try {
          final itemId = await _findDnServerItemId(
            widget.dio,
            uuid: widget.uuid,
            boxNumber: widget.box['box_number'],
            inventoryId: '${_selectedItem!['id'] ?? ''}',
            name: _displayName(_selectedItem!),
            serial: '${_selectedItem!['sn'] ?? ''}',
          );
          if (itemId == null) {
            photoWarning =
                'The item was saved, but its photo could not be linked. Please reopen the item and try again.';
          } else {
            await _uploadDnItemPhotos(widget.dio,
                uuid: widget.uuid, itemId: itemId, photos: _photos);
            newItem['id'] = itemId;
            final photoIds = await _loadDnItemPhotoIds(widget.dio, widget.uuid);
            newItem['photo_ids'] = photoIds['$itemId'] ?? const <int>[];
            newItem['photo_count'] = (newItem['photo_ids'] as List).length;
          }
        } catch (e) {
          photoWarning = 'The item was saved, but the photo upload failed: $e';
        }
      }

      // Server sudah menerima item. Simpan juga ke box dan cache lokal agar
      // halaman sebelumnya langsung menampilkannya tanpa menunggu reload detail.
      final items = (widget.box['items'] as List? ?? <Map<String, dynamic>>[]);
      items.add(_normalizeDnItem(newItem));
      widget.box['items'] = items;
      await _rememberDnBoxItems(
        widget.uuid,
        widget.box['box_number'],
        items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
      if (!mounted) return;
      if (photoWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(photoWarning), backgroundColor: AppColors.warning));
        await Future<void>.delayed(const Duration(milliseconds: 750));
      }
      Navigator.pop(context, true);
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to add equipment: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _displayName(Map<String, dynamic> item) {
    return _equipmentDisplayName(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text('Add Equipment BOX${widget.box['box_number']}'),
        actions: [
          IconButton(
            onPressed: _openScanPage,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            onPressed: _loadInventory,
            icon: const Icon(Icons.refresh),
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
                hintText: 'Cari asset code, model, serial number',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _loadInventory,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('No equipment found'))
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final selected = _selectedItem?['id'] == item['id'];
                          return Card(
                            margin: EdgeInsets.only(bottom: 10.h),
                            color: selected
                                ? AppColors.primary.withOpacity(0.08)
                                : null,
                            child: ListTile(
                              onTap: () => setState(() => _selectedItem = item),
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                              ),
                              title: Text(
                                _displayName(item),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                'Asset: ${item['asset_code'] ?? '-'}\nSN: ${item['sn'] ?? '-'}\nGroup: ${item['group'] ?? '-'}',
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedItem == null
                      ? 'Select equipment from the list'
                      : 'Selected equipment: ${_displayName(_selectedItem!)}',
                  style:
                      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyController,
                        enabled: !widget.readOnly,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                TextField(
                  controller: _notesController,
                  enabled: !widget.readOnly,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                SizedBox(height: 12.h),
                _DnItemPhotoPicker(
                  photos: _photos,
                  enabled: !widget.readOnly,
                  onChanged: (photos) => setState(() => _photos = photos),
                ),
                SizedBox(height: 14.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving || widget.readOnly ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child:
                                const CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline),
                    label: const Text('Save to Box'),
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

class DnOtherItemPage extends StatefulWidget {
  final String uuid;
  final Map<String, dynamic> box;
  final Dio dio;
  final bool useSample;
  final bool readOnly;
  final String? initialSerial;

  const DnOtherItemPage({
    Key? key,
    required this.uuid,
    required this.box,
    required this.dio,
    required this.useSample,
    required this.readOnly,
    this.initialSerial,
  }) : super(key: key);

  @override
  State<DnOtherItemPage> createState() => _DnOtherItemPageState();
}

class _DnOtherItemPageState extends State<DnOtherItemPage> {
  final _name = TextEditingController();
  final _serial = TextEditingController();
  final _value = TextEditingController();
  final _qty = TextEditingController(text: '1');
  bool _saving = false;
  bool _changed = false;
  dynamic _editingItemId;
  int? _editingIndex;
  List<Map<String, dynamic>> _suggestions = const [];
  Timer? _suggestionDebounce;
  List<XFile> _photos = const [];

  List<Map<String, dynamic>> get _items =>
      (widget.box['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  void initState() {
    super.initState();
    _serial.text = widget.initialSerial?.trim() ?? '';
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _name.dispose();
    _serial.dispose();
    _value.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _onNameChanged(String value) {
    _suggestionDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadSuggestions(value.trim());
    });
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final response = await widget.dio.get(
        '/api/delivery-notes/manual-suggestions',
        queryParameters: {'search': query},
      );
      final body = _dnResponseMap(response.data);
      if (!mounted || _name.text.trim() != query) return;
      setState(() {
        _suggestions = (body['data'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
    } catch (_) {
      // Autocomplete bersifat bantuan; pengguna tetap bisa input manual.
    }
  }

  void _applySuggestion(Map<String, dynamic> item) {
    setState(() {
      _name.text = '${item['name'] ?? ''}';
      _serial.text = '${item['serialNumber'] ?? ''}';
      if (_value.text.trim().isEmpty) _value.text = '${item['value'] ?? ''}';
      _suggestions = const [];
    });
  }

  Future<void> _scanAndFill() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const DnEquipmentScanPage()),
    );
    final rawCode = scanned?.trim() ?? '';
    if (rawCode.isEmpty || !mounted) return;
    final parsed = QrScanResult.fromRawData(rawCode);
    // QR internal dapat berisi asset code atau baris "SN:"; barcode biasa
    // tetap dipakai apa adanya agar masuk ke Serial Number bila tak terdaftar.
    final code = parsed.assetCode.isNotEmpty
        ? parsed.assetCode
        : parsed.sn.isNotEmpty
            ? parsed.sn
            : rawCode;

    try {
      final response = await widget.dio.get(
        '/api/delivery-notes/inventory',
        queryParameters: {'search': code},
      );
      final body = _dnResponseMap(response.data);
      final candidates = (body['data'] as List? ?? const []).whereType<Map>();
      Map<String, dynamic>? registered;
      for (final raw in candidates) {
        final row = Map<String, dynamic>.from(raw);
        final assetCode = '${row['assetCode'] ?? ''}'.trim().toLowerCase();
        final serialNumber =
            '${row['serialNumber'] ?? ''}'.trim().toLowerCase();
        if (assetCode == code.toLowerCase() ||
            serialNumber == code.toLowerCase()) {
          registered = row;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _serial.text =
            registered == null ? code : '${registered['serialNumber'] ?? code}';
        if (registered != null) {
          _name.text = '${registered['name'] ?? ''}';
          _value.text = '${registered['value'] ?? ''}';
        }
        _suggestions = const [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(registered == null
              ? 'Barcode not found in inventory. It was placed in the Serial Number field.'
              : 'Registered asset found. Name and serial number were filled in.'),
          backgroundColor:
              registered == null ? AppColors.warning : AppColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _serial.text = code);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The barcode was saved as the Serial Number.'),
            backgroundColor: AppColors.warning),
      );
    }
  }

  void _fillForm(Map<String, dynamic> item, int index) {
    _name.text =
        _equipmentDisplayName(item) == '-' ? '' : _equipmentDisplayName(item);
    _serial.text = _equipmentDisplaySerial(item) == '-'
        ? ''
        : _equipmentDisplaySerial(item);
    _value.text = '${item['equipment_value'] ?? item['value'] ?? ''}';
    _qty.text = '${item['equipment_qty'] ?? item['qty'] ?? 1}';
    setState(() {
      _editingItemId = item['id'];
      _editingIndex = index;
    });
  }

  void _resetForm() {
    _name.clear();
    _serial.clear();
    _value.clear();
    _qty.text = '1';
    _editingItemId = null;
    _editingIndex = null;
    _photos = const [];
  }

  Future<void> _deleteItem(Map<String, dynamic> item, int index) async {
    if (widget.readOnly) return;
    try {
      if (!widget.useSample && item['id'] != null) {
        await widget.dio.delete(
            '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/items/${item['id']}');
      }
      final items = (widget.box['items'] as List? ?? <Map<String, dynamic>>[]);
      if (index >= 0 && index < items.length) {
        items.removeAt(index);
      }
      widget.box['items'] = items;
      await _rememberDnBoxItems(
        widget.uuid,
        widget.box['box_number'],
        items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
      _changed = true;
      if (_editingItemId == item['id']) {
        _resetForm();
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Item deleted.'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to delete item: $e'),
            backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter the equipment name first.'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final wasEditing = _editingIndex != null;
      final newItem = <String, dynamic>{
        'id': _editingItemId ?? DateTime.now().millisecondsSinceEpoch,
        'equipment_name': _name.text.trim(),
        'equipment_sn': _serial.text.trim(),
        'equipment_qty': _qty.text.trim().isEmpty ? '1' : _qty.text.trim(),
        'equipment_value':
            _value.text.trim().isEmpty ? '0' : _value.text.trim(),
      };
      int? savedItemId;

      if (!widget.useSample) {
        if (_editingItemId != null) {
          final original =
              (_editingIndex != null && _editingIndex! < _items.length)
                  ? _items[_editingIndex!]
                  : newItem;
          savedItemId = await _findDnServerItemId(
            widget.dio,
            uuid: widget.uuid,
            boxNumber: widget.box['box_number'],
            name: _equipmentDisplayName(original),
            serial: _equipmentDisplaySerial(original),
          );
          savedItemId ??= int.tryParse('$_editingItemId');
          if (savedItemId == null)
            throw Exception(
                'The server item could not be found. Please refresh the box and try again.');
          final response = await widget.dio.patch(
              '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/items/$savedItemId',
              data: {
                'boxNumber': widget.box['box_number'],
                'name': _name.text.trim(),
                'serialNumber': _serial.text.trim(),
                'quantity': _qty.text.trim().isEmpty ? 1 : _qty.text.trim(),
                'value': _value.text.trim().isEmpty ? 0 : _value.text.trim(),
                'notes': '',
              });
          if (response.statusCode != 200)
            throw Exception('The item could not be updated.');
          newItem['id'] = savedItemId;
        } else {
          final response = await widget.dio.post(
              '/api/delivery-notes/${Uri.encodeComponent(widget.uuid)}/items/manual',
              data: {
                'boxNumber': widget.box['box_number'],
                'name': _name.text.trim(),
                'serialNumber': _serial.text.trim(),
                'value': _value.text.trim().isEmpty ? 0 : _value.text.trim(),
                'quantity': _qty.text.trim().isEmpty ? 1 : _qty.text.trim(),
              });
          if (response.statusCode != 201) {
            final body = _dnResponseMap(response.data);
            throw Exception('${body['message'] ?? 'Unable to add the item.'}');
          }
        }
      }

      String? photoWarning;
      if (!widget.useSample && _photos.isNotEmpty) {
        try {
          final itemId = savedItemId ??
              await _findDnServerItemId(
                widget.dio,
                uuid: widget.uuid,
                boxNumber: widget.box['box_number'],
                name: _name.text.trim(),
                serial: _serial.text.trim(),
              );
          if (itemId == null) {
            photoWarning =
                'The item was saved, but its photo could not be linked. Please reopen the item and try again.';
          } else {
            await _uploadDnItemPhotos(widget.dio,
                uuid: widget.uuid, itemId: itemId, photos: _photos);
            newItem['id'] = itemId;
            final photoIds = await _loadDnItemPhotoIds(widget.dio, widget.uuid);
            newItem['photo_ids'] = photoIds['$itemId'] ?? const <int>[];
            newItem['photo_count'] = (newItem['photo_ids'] as List).length;
          }
        } catch (e) {
          photoWarning = 'The item was saved, but the photo upload failed: $e';
        }
      }

      final items = (widget.box['items'] as List? ?? <Map<String, dynamic>>[]);
      if (_editingIndex != null &&
          _editingIndex! >= 0 &&
          _editingIndex! < items.length) {
        items[_editingIndex!] = newItem;
      } else {
        items.add(newItem);
      }
      widget.box['items'] = items;
      await _rememberDnBoxItems(
        widget.uuid,
        widget.box['box_number'],
        items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );

      _resetForm();
      _changed = true;

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(photoWarning ??
              (wasEditing
                  ? 'Item updated successfully.'
                  : 'Item added successfully.')),
          backgroundColor:
              photoWarning == null ? AppColors.success : AppColors.warning,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to add item: $e'),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.lightBackground,
        appBar: AppBar(
          title: const Text('Add Other Item'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            TextField(
              controller: _name,
              enabled: !widget.readOnly,
              onChanged: _onNameChanged,
              decoration: const InputDecoration(
                labelText: 'Equipment Name',
                hintText: 'Ketik minimal 2 huruf untuk mencari',
              ),
            ),
            if (_suggestions.isNotEmpty) ...[
              SizedBox(height: 6.h),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: _suggestions
                      .take(5)
                      .map((item) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.inventory_2_outlined,
                                size: 19),
                            title: Text('${item['name'] ?? '-'}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle:
                                Text('SN: ${item['serialNumber'] ?? '-'}'),
                            onTap: () => _applySuggestion(item),
                          ))
                      .toList(),
                ),
              ),
            ],
            SizedBox(height: 12.h),
            TextField(
              controller: _serial,
              enabled: !widget.readOnly,
              decoration: const InputDecoration(labelText: 'Serial Number'),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _value,
              enabled: !widget.readOnly,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Equipment Value'),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _qty,
              enabled: !widget.readOnly,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            SizedBox(height: 12.h),
            _DnItemPhotoPicker(
              photos: _photos,
              enabled: !widget.readOnly,
              onChanged: (photos) => setState(() => _photos = photos),
              onScan: _scanAndFill,
            ),
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving || widget.readOnly ? null : _save,
                child: _saving
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: const CircularProgressIndicator(strokeWidth: 2))
                    : Text(_editingIndex != null ? 'Update' : 'Save'),
              ),
            ),
            if (_editingIndex != null) ...[
              SizedBox(height: 10.h),
              OutlinedButton(
                onPressed: _saving ? null : () => setState(_resetForm),
                child: const Text('Cancel Edit'),
              ),
            ],
            SizedBox(height: 20.h),
            Text(
              'Item dalam BOX',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 10.h),
            if (_items.isEmpty)
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Text(
                  'There are no other items in this box yet.',
                  style: TextStyle(
                      fontSize: 13.sp, color: AppColors.textSecondary),
                ),
              )
            else
              ..._items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final name = _equipmentDisplayName(item);
                final sn = _equipmentDisplaySerial(item);
                return Card(
                  margin: EdgeInsets.only(bottom: 10.h),
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined,
                        color: AppColors.primary),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'SN: $sn\nQty: ${item['equipment_qty'] ?? item['qty'] ?? 1}'),
                    isThreeLine: true,
                    trailing: widget.readOnly
                        ? null
                        : SizedBox(
                            width: 96.w,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  onPressed: () => _fillForm(item, index),
                                  icon: const Icon(Icons.edit_outlined,
                                      color: AppColors.primary),
                                  tooltip: 'Edit item',
                                ),
                                IconButton(
                                  onPressed: () => _deleteItem(item, index),
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.error),
                                  tooltip: 'Delete item',
                                ),
                              ],
                            ),
                          ),
                  ),
                );
              }),
            SizedBox(height: 20.h),
          ],
        ),
      ),
    );
  }
}

class DnEquipmentScanPage extends StatefulWidget {
  const DnEquipmentScanPage({Key? key}) : super(key: key);

  @override
  State<DnEquipmentScanPage> createState() => _DnEquipmentScanPageState();
}

class _DnEquipmentScanPageState extends State<DnEquipmentScanPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_handled) return;
    if (state == AppLifecycleState.resumed) {
      _restartScannerAfterResume();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller.stop();
    }
  }

  Future<void> _restartScannerAfterResume() async {
    try {
      await _controller.start();
    } catch (_) {
      // The camera may still be being released by Android. The next visit can
      // safely start a new scanner session.
    }
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;

      _handled = true;
      _controller.stop();
      // Kirim data mentah supaya pemanggil dapat mengenali QR asset, QR dengan
      // SN, maupun barcode produk umum tanpa kehilangan nilai aslinya.
      Navigator.pop(context, raw.trim());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Equipment'),
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleCapture,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 28.h),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black87,
                    Colors.transparent,
                  ],
                ),
              ),
              child: Text(
                'Point the camera at the equipment QR code. Once detected, the equipment search will fill automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OtherItemDialogState extends State<_OtherItemDialog> {
  final _name = TextEditingController();
  final _serial = TextEditingController();
  final _value = TextEditingController();
  final _qty = TextEditingController(text: '1');

  @override
  void dispose() {
    _name.dispose();
    _serial.dispose();
    _value.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Other Item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Equipment Name')),
            TextField(
                controller: _serial,
                decoration: const InputDecoration(labelText: 'Serial Number')),
            TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Equipment Value')),
            TextField(
                controller: _qty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity')),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'equipment_name': _name.text.trim(),
              'serial_number': _serial.text.trim(),
              'value': _value.text.trim(),
              'qty': _qty.text.trim(),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class DnListItem {
  final String uuid;
  final String danNumber;
  final String jobNumber;
  final String destination;
  final String dispatchBy;
  final String receivedBy;
  final String createdDate;
  final String deliveryDate;
  final String status;
  final int statusId;

  const DnListItem({
    required this.uuid,
    required this.danNumber,
    required this.jobNumber,
    required this.destination,
    required this.dispatchBy,
    required this.receivedBy,
    required this.createdDate,
    required this.deliveryDate,
    required this.status,
    required this.statusId,
  });

  factory DnListItem.fromJson(Map<String, dynamic> json) {
    final rawDanNumber =
        '${json['danNumber'] ?? json['dan_number'] ?? ''}'.trim();
    return DnListItem(
      uuid: '${json['uuid'] ?? ''}',
      danNumber:
          rawDanNumber.isEmpty ? 'Draft — assigned on finish' : rawDanNumber,
      jobNumber: '${json['jobNumber'] ?? json['job_number'] ?? '-'}',
      destination: '${json['destination'] ?? '-'}',
      dispatchBy: '${json['dispatchedBy'] ?? json['dispatch_by'] ?? '-'}',
      receivedBy: '${json['receivedBy'] ?? json['received_by'] ?? '-'}',
      createdDate:
          '${json['createdDate'] ?? json['created_date'] ?? json['modified_date'] ?? '-'}',
      deliveryDate: '${json['deliveryDate'] ?? json['delivery_date'] ?? '-'}',
      status: '${json['status'] ?? '-'}',
      statusId:
          int.tryParse('${json['statusId'] ?? json['status_id'] ?? 0}') ?? 0,
    );
  }
}

class _DnCard extends StatelessWidget {
  final DnListItem item;
  final VoidCallback onTap;

  const _DnCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = item.statusId == 2
        ? AppColors.warning
        : item.statusId == 4
            ? AppColors.success
            : AppColors.primary;
    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(color: AppColors.border.withOpacity(0.7)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 11.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.danNumber,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15.sp),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999.r)),
                    child: Text(item.status,
                        style: TextStyle(
                            color: color,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Text(
                '${item.jobNumber}  •  ${item.destination}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 11.sp, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listInfoRow(
    String label,
    String value, {
    int maxLines = 2,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78.w,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.sp,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _datePill(String label, String value, {required IconData icon}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16.r, color: AppColors.textSecondary),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  value.trim().isEmpty ? '-' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
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

class _JobInfo extends StatelessWidget {
  final Map<String, dynamic> dn;
  final bool expanded;
  final VoidCallback onToggle;

  const _JobInfo({
    required this.dn,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final jobNumber = _firstNonEmptyValue(
      dn,
      ['job_number_text', 'job_number', 'djn'],
      fallback: '-',
    );
    final destination = _firstNonEmptyValue(
      dn,
      ['delivery_address_text', 'delivery_address', 'destination'],
      fallback: '-',
    );
    final dispatchedBy = _firstNonEmptyValue(
      dn,
      ['dispatch_by_name', 'dispatch_by', 'created_user'],
      fallback: '-',
    );
    final sentDate = _firstNonEmptyValue(
      dn,
      ['delivery_date', 'sent_date'],
      fallback: '-',
    );
    final receivedDate = _firstNonEmptyValue(
      dn,
      ['received_date', 'receive_date', 'updated_date'],
      fallback: '-',
    );

    return Card(
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              child: Row(
                children: [
                  Expanded(
                      child: Text('Job Info',
                          style: TextStyle(
                              fontSize: 16.sp, fontWeight: FontWeight.w800))),
                  Icon(expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded),
                ],
              ),
            ),
            SizedBox(height: 8.h),
            _ReadOnlyTile(label: 'DN No', value: '${dn['dan_number'] ?? '-'}'),
            _ReadOnlyTile(label: 'Job Number', value: jobNumber),
            if (expanded) ...[
              _ReadOnlyTile(
                label: 'Destination',
                value: destination,
              ),
              _ReadOnlyTile(
                label: 'Dispatched By',
                value: dispatchedBy,
              ),
              Row(
                children: [
                  Expanded(
                    child: _ReadOnlyTile(
                      label: 'Sent Date',
                      value: sentDate,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _ReadOnlyTile(
                      label: 'Received Date',
                      value: receivedDate,
                    ),
                  ),
                ],
              ),
              _ReadOnlyTile(
                  label: 'Proforma No',
                  value: '${dn['proforma_number'] ?? '-'}'),
              _ReadOnlyTile(
                  label: 'Cost Code', value: '${dn['cost_code_text'] ?? '-'}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyTile extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12.sp)),
          SizedBox(height: 4.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(value,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _BoxSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool plain;

  const _BoxSummaryRow({
    required this.label,
    required this.value,
    this.plain = false,
  });

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 5.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp)),
        SizedBox(height: 4.h),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Text(value,
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  final String status;

  const _StepHeader({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalizedStatus = status.toLowerCase().trim();
    final statusColor = normalizedStatus == 'preparation'
        ? AppColors.warning
        : normalizedStatus == 'sent'
            ? AppColors.success
            : normalizedStatus == 'received'
                ? AppColors.info
                : AppColors.primary;
    final currentStep = _stepIndexForStatus(normalizedStatus);
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppColors.primary),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  'Flow DN',
                  style:
                      TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999.r),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.sp),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              _flowStep('Customize', currentStep == 0, currentStep > 0),
              _flowConnector(),
              _flowStep('Sender', currentStep == 1, currentStep > 1),
              _flowConnector(),
              _flowStep('Dispatch', currentStep == 2, currentStep > 2),
              _flowConnector(),
              _flowStep('Review', currentStep >= 3, currentStep >= 3),
            ],
          ),
        ],
      ),
    );
  }

  int _stepIndexForStatus(String status) {
    if (status == 'sent' || status == 'received') {
      return 3;
    }
    if (status.contains('dispatch')) {
      return 2;
    }
    if (status.contains('sender')) {
      return 1;
    }
    return 0;
  }

  Widget _flowStep(String label, bool active, bool done) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color:
                  active || done ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              done ? Icons.check_rounded : Icons.circle_outlined,
              size: 16,
              color: active || done ? Colors.white : AppColors.textTertiary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
              color: active || done
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _flowConnector() {
    return Container(
      width: 16.w,
      height: 2.h,
      margin: EdgeInsets.only(bottom: 18.h),
      color: AppColors.border,
    );
  }
}

class _FormSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _FormSectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32.w,
                  height: 32.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 18.r),
                ),
                SizedBox(width: 10.w),
                Text(
                  title,
                  style:
                      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: const Center(child: Text('No box yet. Please add a box first.')),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            SizedBox(height: 8.h),
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: 12.h),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ApiUnavailableState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ApiUnavailableState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
            SizedBox(height: 8.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary),
            ),
            SizedBox(height: 12.h),
            Text(
              'This fallback view does not show demo data.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, color: AppColors.textTertiary),
            ),
            SizedBox(height: 16.h),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

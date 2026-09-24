import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../data/datasources/warehouse_movement_remote_datasource.dart';

class WarehouseMovementAddConsumablePage extends StatefulWidget {
  final String movementUuid;

  const WarehouseMovementAddConsumablePage({
    super.key,
    required this.movementUuid,
  });

  @override
  State<WarehouseMovementAddConsumablePage> createState() =>
      _WarehouseMovementAddConsumablePageState();
}

class _WarehouseMovementAddConsumablePageState
    extends State<WarehouseMovementAddConsumablePage> {
  final _itemNameController = TextEditingController();
  final _itemCodeController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  bool _loadingUoms = true;
  bool _saving = false;
  List<Map<String, dynamic>> _uomOptions = const [];
  String? _selectedUomId;
  String? _selectedUomName;

  @override
  void initState() {
    super.initState();
    _loadUoms();
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _itemCodeController.dispose();
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
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

  Future<void> _loadUoms() async {
    setState(() => _loadingUoms = true);
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

      final response = await dio.get('/api/inventory/form-data');
      final body = _responseMap(response.data);
      final data = Map<String, dynamic>.from(body['data'] ?? const {});
      final rows = (data['inventory_uom'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        _uomOptions = rows;
        if (rows.isNotEmpty) {
          _selectedUomId = '${rows.first['id'] ?? ''}';
          _selectedUomName = '${rows.first['name'] ?? rows.first['inventory_uom'] ?? 'pcs'}';
        }
        _loadingUoms = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uomOptions = const [
          {'id': 'pcs', 'name': 'pcs'},
        ];
        _selectedUomId = 'pcs';
        _selectedUomName = 'pcs';
        _loadingUoms = false;
      });
    }
  }

  Future<void> _save() async {
    if (_itemNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the item name first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if ((_selectedUomName ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a UOM first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await sl<WarehouseMovementRemoteDataSource>().addMovementItem(
        uuid: widget.movementUuid,
        payload: {
          'item_type': 'consumable',
          'item_name': _itemNameController.text.trim(),
          'item_code': _itemCodeController.text.trim(),
          'qty': _qtyController.text.trim().isEmpty ? '1' : _qtyController.text.trim(),
          'uom': (_selectedUomName ?? '').trim(),
          'uom_id': (_selectedUomId ?? '').trim(),
          'remarks': _notesController.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${response['message'] ?? 'Consumable added successfully.'}'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add consumable: $e'),
          backgroundColor: AppColors.error,
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
      appBar: AppBar(title: const Text('Add Consumable')),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          TextField(
            controller: _itemNameController,
            decoration: const InputDecoration(labelText: 'Item Name'),
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _itemCodeController,
            decoration: const InputDecoration(labelText: 'Item Code'),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedUomId,
                  isExpanded: true,
                  items: _uomOptions
                      .map(
                        (option) => DropdownMenuItem<String>(
                          value: '${option['id'] ?? ''}',
                          child: Text(
                            '${option['name'] ?? option['inventory_uom'] ?? '-'}',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loadingUoms
                      ? null
                      : (value) {
                          final selected = _uomOptions.cast<Map<String, dynamic>?>().firstWhere(
                                (row) => '${row?['id'] ?? ''}' == '$value',
                                orElse: () => null,
                              );
                          setState(() {
                            _selectedUomId = value;
                            _selectedUomName = selected == null
                                ? null
                                : '${selected['name'] ?? selected['inventory_uom'] ?? '-'}';
                          });
                        },
                  decoration: InputDecoration(
                    labelText: _loadingUoms ? 'UOM (loading...)' : 'UOM',
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          TextField(
            controller: _notesController,
            minLines: 3,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
          SizedBox(height: 20.h),
          ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: Text(_saving ? 'Saving...' : 'Add to Movement'),
          ),
        ],
      ),
    );
  }
}

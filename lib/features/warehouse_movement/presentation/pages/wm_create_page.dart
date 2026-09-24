import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'dart:convert';

import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../data/datasources/warehouse_movement_remote_datasource.dart';
import '../../domain/entities/warehouse_movement_create_data.dart';
import 'wm_detail_page.dart';

class WarehouseMovementCreatePage extends StatefulWidget {
  const WarehouseMovementCreatePage({super.key});

  @override
  State<WarehouseMovementCreatePage> createState() =>
      _WarehouseMovementCreatePageState();
}

class _WarehouseMovementCreatePageState
    extends State<WarehouseMovementCreatePage> {
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _requesterController = TextEditingController();

  bool _isLoading = true;
  bool _saving = false;
  String? _errorMessage;
  WarehouseMovementCreateData? _createData;

  WarehouseMovementOption? _selectedTransactionType;
  WarehouseMovementOption? _selectedPurpose;
  WarehouseMovementOption? _selectedSourceLocation;
  WarehouseMovementOption? _selectedDestinationLocation;
  WarehouseMovementOption? _selectedProject;
  DateTime _movementDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCreateData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _requesterController.dispose();
    super.dispose();
  }

  Future<void> _loadCreateData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await sl<WarehouseMovementRemoteDataSource>().getCreateData();
      final normalized = _normalizeCreateData(data);

      setState(() {
        _createData = normalized;
        _selectedTransactionType = normalized.transactionTypes.isNotEmpty
            ? normalized.transactionTypes.first
            : null;
        _selectedPurpose =
            normalized.purposes.isNotEmpty ? normalized.purposes.first : null;
        _selectedSourceLocation = normalized.locations.isNotEmpty
            ? normalized.locations.first
            : null;
        _selectedDestinationLocation = normalized.locations.length > 1
            ? normalized.locations[1]
            : normalized.locations.isNotEmpty
                ? normalized.locations.first
                : null;
        _selectedProject =
            normalized.projects.isNotEmpty ? normalized.projects.first : null;
        _requesterController.text = normalized.requester?.name ?? '-';
        _isLoading = false;
      });
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[WM][CREATE_DATA] $message');
      setState(() {
        _createData = WarehouseMovementCreateData(
          transactionTypes: _fallbackTransactionTypes,
          purposes: _fallbackPurposes,
          locations: const [],
          projects: const [],
          requester: const WarehouseMovementOption(
            id: 'self',
            name: 'Current User',
          ),
        );
        _selectedTransactionType = _fallbackTransactionTypes.first;
        _selectedPurpose = _fallbackPurposes.first;
        _selectedSourceLocation = null;
        _selectedDestinationLocation = null;
        _selectedProject = null;
        _requesterController.text = 'Current User';
        _errorMessage = message.isNotEmpty
            ? 'Failed to load master data: $message'
            : 'Master data is not available from the server yet. Project and location must come from the backend.';
        _isLoading = false;
      });
    }
  }

  WarehouseMovementCreateData _normalizeCreateData(
    WarehouseMovementCreateData data,
  ) {
    final transactionTypes = data.transactionTypes.isNotEmpty
        ? data.transactionTypes
        : _fallbackTransactionTypes;
    final purposes = data.purposes.isNotEmpty ? data.purposes : _fallbackPurposes;
    final locations = data.locations;
    final projects = data.projects;

    return WarehouseMovementCreateData(
      transactionTypes: transactionTypes,
      purposes: purposes,
      locations: locations,
      projects: projects,
      requester: data.requester,
    );
  }

  List<WarehouseMovementOption> get _fallbackTransactionTypes => const [
        WarehouseMovementOption(id: 'issue_out', name: 'Issue Out'),
        WarehouseMovementOption(id: 'return_in', name: 'Return In'),
        WarehouseMovementOption(id: 'transfer', name: 'Transfer'),
      ];

  List<WarehouseMovementOption> get _fallbackPurposes => const [
        WarehouseMovementOption(id: 'project', name: 'Project'),
        WarehouseMovementOption(id: 'office', name: 'Office'),
        WarehouseMovementOption(id: 'warehouse_use', name: 'Warehouse Use'),
        WarehouseMovementOption(id: 'maintenance', name: 'Maintenance'),
      ];

  bool get _requiresProject =>
      (_selectedPurpose?.name.toLowerCase() ?? '').contains('project');

  Future<void> _pickMovementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _movementDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      setState(() {
        _movementDate = picked;
      });
    }
  }

  Map<String, dynamic> _parseResponseBody(dynamic rawData) {
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

  bool get _canSaveDraft {
    if (_saving || _selectedTransactionType == null || _selectedPurpose == null) {
      return false;
    }
    if (_selectedSourceLocation == null) {
      return false;
    }
    if (_requiresProject && _selectedProject == null) {
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _wmHeaders() async {
    final cookie = await AppAuthSession.getStoredWebSessionCookie();
    final token = await AppAuthSession.resolveApiBearerToken();
    if ((cookie ?? '').isNotEmpty || (token ?? '').isNotEmpty) {
      return {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
    }

    final staticToken = AppConstants.apiStaticToken.trim();
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (staticToken.isNotEmpty) ...{
        'Authorization': 'Bearer $staticToken',
        'X-API-Key': staticToken,
        'X-API-Token': staticToken,
        'X-Api-Secret': staticToken,
      },
    };
  }

  Future<void> _saveDraft() async {
    if (!_canSaveDraft) {
      _showSnack(
        'Please complete transaction type, purpose, source location, and project if required.',
        true,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.baseUrl,
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: await _wmHeaders(),
        ),
      );

      final response = await dio.post(
        '/api/warehouse-movement/create',
        data: {
          'transaction_type': _selectedTransactionType!.id,
          'purpose': _selectedPurpose!.id,
          'source_location_id': _selectedSourceLocation!.id,
          'destination_location_id': _selectedDestinationLocation?.id,
          'project_id': _selectedProject?.id,
          'movement_date': _formatDate(_movementDate),
          'notes': _notesController.text.trim(),
        },
      );

      final body = _parseResponseBody(response.data);
      debugPrint('[WM][CREATE][HTTP] status=${response.statusCode} body=${response.data}');

      if (response.statusCode == 200 && body['status'] == true) {
        if (!mounted) return;
        _showSnack('Draft created successfully.', false);
        final movementNumber =
            '${body['data']?['movement_number'] ?? body['data']?['uuid'] ?? 'Movement Detail'}';
        final uuid = '${body['data']?['uuid'] ?? ''}'.trim();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => WarehouseMovementDetailPage(
              uuid: uuid,
              movementNumber: movementNumber,
            ),
          ),
          result: true,
        );
        return;
      }

      final message = '${body['message'] ?? 'Failed to create draft.'}'.trim();
      _showSnack(message.isEmpty ? 'Failed to create draft.' : message, true);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String message, bool isError) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Create Movement'),
        actions: [
          IconButton(
            onPressed: _loadCreateData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(16.w),
              children: [
                if (_errorMessage != null) ...[
                  _InfoBanner(message: _errorMessage!),
                  SizedBox(height: 12.h),
                ],
                _sectionCard(
                  title: 'Movement Header',
                  children: [
                    _DropdownField(
                      label: 'Transaction Type',
                      value: _selectedTransactionType,
                      items: _createData?.transactionTypes ?? const [],
                      onChanged: (value) {
                        setState(() => _selectedTransactionType = value);
                      },
                    ),
                    _DropdownField(
                      label: 'Purpose',
                      value: _selectedPurpose,
                      items: _createData?.purposes ?? const [],
                      onChanged: (value) {
                        setState(() {
                          _selectedPurpose = value;
                          if (!_requiresProject) {
                            _selectedProject = null;
                          } else if ((_createData?.projects ?? const []).isNotEmpty &&
                              _selectedProject == null) {
                            _selectedProject = _createData!.projects.first;
                          }
                        });
                      },
                    ),
                    (_createData?.locations ?? const []).isEmpty
                        ? const _UnavailableField(label: 'Source Location')
                        : _DropdownField(
                            label: 'Source Location',
                            value: _selectedSourceLocation,
                            items: _createData?.locations ?? const [],
                            onChanged: (value) {
                              setState(() => _selectedSourceLocation = value);
                            },
                          ),
                    (_createData?.locations ?? const []).isEmpty
                        ? const _UnavailableField(label: 'Destination Location')
                        : _DropdownField(
                            label: 'Destination Location',
                            value: _selectedDestinationLocation,
                            items: _createData?.locations ?? const [],
                            onChanged: (value) {
                              setState(() => _selectedDestinationLocation = value);
                            },
                          ),
                    if (_requiresProject)
                      (_createData?.projects ?? const []).isEmpty
                          ? const _UnavailableField(label: 'Project')
                          : _DropdownField(
                              label: 'Project',
                              value: _selectedProject,
                              items: _createData?.projects ?? const [],
                              onChanged: (value) {
                                setState(() => _selectedProject = value);
                              },
                            ),
                    _ReadonlyField(
                      label: 'Requester',
                      controller: _requesterController,
                      prefixIcon: Icons.person_outline_rounded,
                    ),
                    _ActionField(
                      label: 'Movement Date',
                      value: _formatDate(_movementDate),
                      icon: Icons.calendar_today_outlined,
                      onTap: _pickMovementDate,
                    ),
                    _NotesField(controller: _notesController),
                  ],
                ),
                SizedBox(height: 16.h),
                _sectionCard(
                  title: 'Items',
                  children: const [
                    _ActionPlaceholder(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'Add Equipment',
                      subtitle: 'Scan asset QR or select from equipment inventory.',
                    ),
                    _ActionPlaceholder(
                      icon: Icons.inventory_2_outlined,
                      title: 'Add Consumable',
                      subtitle: 'Select stock item and define quantity.',
                    ),
                  ],
                ),
                SizedBox(height: 24.h),
                ElevatedButton.icon(
                  onPressed: _canSaveDraft ? _saveDraft : null,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving...' : 'Save Draft'),
                ),
              ],
            ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    final spacedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spacedChildren.add(children[i]);
      if (i != children.length - 1) {
        spacedChildren.add(SizedBox(height: 12.h));
      }
    }

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 14.h),
          ...spacedChildren,
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    return '$yyyy-$mm-$dd';
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;

  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18.r),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.sp,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final WarehouseMovementOption? value;
  final List<WarehouseMovementOption> items;
  final ValueChanged<WarehouseMovementOption?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _UnavailableField(label: label);
    }
    return DropdownButtonFormField<WarehouseMovementOption>(
      isExpanded: true,
      value: items.any((item) => item.id == value?.id) ? value : null,
      icon: const Icon(Icons.arrow_drop_down_rounded),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<WarehouseMovementOption>(
              value: item,
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) {
        return items
            .map(
              (item) => SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
            .toList();
      },
      onChanged: onChanged,
    );
  }
}

class _UnavailableField extends StatelessWidget {
  final String label;

  const _UnavailableField({required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Not available from server',
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? prefixIcon;

  const _ReadonlyField({
    required this.label,
    required this.controller,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ActionField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16.r),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
          filled: true,
          fillColor: AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16.r),
            borderSide: BorderSide.none,
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 14.sp,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  final TextEditingController controller;

  const _NotesField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 3,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: 'Notes',
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ActionPlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ActionPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Row(
        children: [
          Container(
            width: 42.w,
            height: 42.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 15.r,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

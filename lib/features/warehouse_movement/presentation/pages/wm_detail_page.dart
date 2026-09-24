import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../data/datasources/warehouse_movement_remote_datasource.dart';
import '../../domain/entities/warehouse_movement_detail.dart';
import '../../domain/entities/warehouse_movement_item.dart';
import 'wm_add_consumable_page.dart';
import 'wm_add_equipment_page.dart';

class WarehouseMovementDetailPage extends StatefulWidget {
  final String uuid;
  final String movementNumber;

  const WarehouseMovementDetailPage({
    super.key,
    required this.uuid,
    required this.movementNumber,
  });

  @override
  State<WarehouseMovementDetailPage> createState() =>
      _WarehouseMovementDetailPageState();
}

class _WarehouseMovementDetailPageState
    extends State<WarehouseMovementDetailPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;
  WarehouseMovementDetail? _detail;

  bool get _isDraft => ((_detail?.movement.status) ?? '').toLowerCase() == 'draft';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final detail =
          await sl<WarehouseMovementRemoteDataSource>().getMovementDetail(widget.uuid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _detail = null;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openAddEquipment() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseMovementAddEquipmentPage(
          movementUuid: widget.uuid,
        ),
      ),
    );
    if (changed == true && mounted) {
      _load();
    }
  }

  Future<void> _openAddConsumable() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseMovementAddConsumablePage(
          movementUuid: widget.uuid,
        ),
      ),
    );
    if (changed == true && mounted) {
      _load();
    }
  }

  Future<void> _deleteItem(WarehouseMovementItem item) async {
    if (item.id.trim().isEmpty) {
      _showSnack('Item ID is missing, so the item cannot be deleted.', true);
      return;
    }
    try {
      await sl<WarehouseMovementRemoteDataSource>().deleteMovementItem(
        uuid: widget.uuid,
        itemId: item.id,
      );
      _showSnack('Item deleted successfully.', false);
      _load();
    } catch (e) {
      _showSnack('Failed to delete item: $e', true);
    }
  }

  Future<void> _submitMovement() async {
    setState(() => _submitting = true);
    try {
      final response =
          await sl<WarehouseMovementRemoteDataSource>().submitMovement(
        uuid: widget.uuid,
      );
      _showSnack(
        '${response['message'] ?? 'Movement submitted successfully.'}',
        false,
      );
      await _load();
    } catch (e) {
      _showSnack('Failed to submit movement: $e', true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
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
    final title = _detail?.movement.movementNumber ?? widget.movementNumber;
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _ErrorState(
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : _detail == null
                  ? _ErrorState(
                      message: 'Movement detail is not available.',
                      onRetry: _load,
                    )
                  : ListView(
                      padding: EdgeInsets.all(16.w),
                      children: [
                        _summaryCard(_detail!),
                        SizedBox(height: 16.h),
                        _itemsCard(_detail!.items),
                        if (_isDraft) ...[
                          SizedBox(height: 16.h),
                          _actionsCard(),
                        ],
                        SizedBox(height: 16.h),
                        _logsCard(_detail!.logs),
                      ],
                    ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.all(16.w),
        child: ElevatedButton.icon(
          onPressed: _isDraft && !_submitting ? _submitMovement : null,
          icon: const Icon(Icons.send_outlined),
          label: Text(_submitting ? 'Submitting...' : 'Submit Movement'),
        ),
      ),
    );
  }

  Widget _summaryCard(WarehouseMovementDetail detail) {
    final movement = detail.movement;
    return _infoCard(
      title: 'Summary',
      children: [
        _kv('Transaction Type', movement.transactionTypeText),
        _kv('Purpose', movement.purposeText),
        _kv('Source', movement.sourceLocationName ?? '-'),
        _kv('Destination', movement.destinationLocationName ?? '-'),
        _kv('Project', movement.projectName ?? '-'),
        _kv('Requester', movement.requesterName ?? '-'),
        _kv('Movement Date', movement.movementDate),
        _kv('Status', movement.statusText),
        if ((movement.notes ?? '').trim().isNotEmpty)
          _kv('Notes', movement.notes!),
      ],
    );
  }

  Widget _itemsCard(List<WarehouseMovementItem> items) {
    return _infoCard(
      title: 'Items',
      children: items.isEmpty
          ? [
              Text(
                'No movement items yet.',
                style: TextStyle(
                  fontSize: 13.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ]
          : items
              .map(
                (item) => Container(
                  margin: EdgeInsets.only(bottom: 10.h),
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.itemName,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'Type: ${item.itemType.isEmpty ? '-' : item.itemType}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'Asset Code: ${item.assetCode?.trim().isNotEmpty == true ? item.assetCode : '-'}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'Serial Number: ${item.serialNumber?.trim().isNotEmpty == true ? item.serialNumber : '-'}',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              'Qty: ${item.qty} ${item.uom?.trim().isNotEmpty == true ? item.uom : ''}'.trim(),
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (item.currentLocationName?.trim().isNotEmpty == true)
                              Text(
                                'Location: ${item.currentLocationName}',
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_isDraft)
                        IconButton(
                          onPressed: () => _deleteItem(item),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.error,
                          ),
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }

  Widget _actionsCard() {
    return _infoCard(
      title: 'Actions',
      children: [
        _ActionTile(
          icon: Icons.qr_code_scanner_rounded,
          title: 'Add Equipment',
          subtitle: 'Select from inventory and attach to this movement.',
          onTap: _openAddEquipment,
        ),
        SizedBox(height: 10.h),
        _ActionTile(
          icon: Icons.inventory_2_outlined,
          title: 'Add Consumable',
          subtitle: 'Add a stock item or manual consumable line.',
          onTap: _openAddConsumable,
        ),
      ],
    );
  }

  Widget _logsCard(List<WarehouseMovementLog> logs) {
    return _infoCard(
      title: 'Logs',
      children: logs.isEmpty
          ? [
              Text(
                'No movement logs yet.',
                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
              ),
            ]
          : logs
              .map(
                (log) => Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.action,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        '${log.actionBy} • ${log.actionAt}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if ((log.notes ?? '').trim().isNotEmpty)
                        Text(
                          log.notes!,
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
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
          SizedBox(height: 10.h),
          ...children,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16.r),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
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
                  SizedBox(height: 2.h),
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
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
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
            Icon(Icons.error_outline, color: AppColors.error, size: 34.r),
            SizedBox(height: 12.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
            SizedBox(height: 16.h),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

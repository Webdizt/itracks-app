import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/foundation.dart';

import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../data/datasources/warehouse_movement_remote_datasource.dart';
import '../../domain/entities/warehouse_movement.dart';
import 'wm_create_page.dart';
import 'wm_detail_page.dart';

class WarehouseMovementListPage extends StatefulWidget {
  final int refreshToken;

  const WarehouseMovementListPage({
    super.key,
    this.refreshToken = 0,
  });

  @override
  State<WarehouseMovementListPage> createState() =>
      _WarehouseMovementListPageState();
}

class _WarehouseMovementListPageState extends State<WarehouseMovementListPage> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _errorMessage;
  List<WarehouseMovement> _movements = const [];
  String _selectedStatus = 'All';

  @override
  void initState() {
    super.initState();
    _loadMovements();
  }

  @override
  void didUpdateWidget(covariant WarehouseMovementListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadMovements();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMovements() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final status = _selectedStatus == 'All' ? null : _selectedStatus.toLowerCase();
      final data = await sl<WarehouseMovementRemoteDataSource>().getMovementList(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        status: status,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _movements = data;
        _loading = false;
      });
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      debugPrint('[WM][LIST] $message');
      if (!mounted) {
        return;
      }

      setState(() {
        _movements = const [];
        _errorMessage = message.isNotEmpty
            ? 'Failed to load warehouse movement data: $message'
            : 'Warehouse movement data is not available from the server yet.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Warehouse Movement'),
        actions: [
          IconButton(
            onPressed: _loadMovements,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: 72.h),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => const WarehouseMovementCreatePage(),
              ),
            );
            if (changed == true && mounted) {
              _loadMovements();
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadMovements,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 96.h),
          children: [
            _SummarySection(data: _movements),
            SizedBox(height: 16.h),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _loadMovements(),
              decoration: InputDecoration(
                hintText: 'Search movement number, project, requester',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _loadMovements,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18.r),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: 14.h,
                ),
              ),
            ),
            SizedBox(height: 14.h),
            SizedBox(
              height: 38.h,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final status in const ['All', 'Draft', 'Submitted', 'Issued', 'Received'])
                    _StatusChip(
                      label: status,
                      isSelected: _selectedStatus == status,
                      onTap: () {
                        setState(() => _selectedStatus = status);
                        _loadMovements();
                      },
                    ),
                ],
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Movements',
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${_movements.length} records',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            if (_errorMessage != null) ...[
              _InfoBanner(message: _errorMessage!),
              SizedBox(height: 12.h),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_movements.isEmpty)
              _EmptyState(
                title: 'No warehouse movement data yet',
                subtitle: 'Once the server list is ready, movements will appear here.',
              )
            else
              ..._movements.map(
                (movement) => Padding(
                  padding: EdgeInsets.only(bottom: 14.h),
                  child: _MovementCard(
                    data: movement,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WarehouseMovementDetailPage(
                            uuid: movement.uuid,
                            movementNumber: movement.movementNumber,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final List<WarehouseMovement> data;

  const _SummarySection({required this.data});

  @override
  Widget build(BuildContext context) {
    final draftCount = data.where((e) => e.statusText.toLowerCase() == 'draft').length;
    final activeCount = data
        .where((e) => ['submitted', 'issued'].contains(e.statusText.toLowerCase()))
        .length;

    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
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
            'Warehouse Overview',
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Track issue, return, and transfer activity from one place.',
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColors.textSecondary,
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: 'Total',
                  value: data.length.toString(),
                  icon: Icons.inventory_2_outlined,
                  color: const Color(0xFFEEF2FF),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _SummaryTile(
                  label: 'Draft',
                  value: draftCount.toString(),
                  icon: Icons.edit_note_outlined,
                  color: const Color(0xFFFFF4E5),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _SummaryTile(
                  label: 'Active',
                  value: activeCount.toString(),
                  icon: Icons.local_shipping_outlined,
                  color: const Color(0xFFEAFBF3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20.r),
          SizedBox(height: 10.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(right: 8.w),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  final WarehouseMovement data;
  final VoidCallback onTap;

  const _MovementCard({
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(data.statusText);
    final canOpen = data.uuid.trim().isNotEmpty;

    return InkWell(
      borderRadius: BorderRadius.circular(24.r),
      onTap: canOpen ? onTap : null,
      child: Container(
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _display(data.movementNumber),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        '${_display(data.transactionTypeText)} | ${_display(data.purposeText)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999.r),
                  ),
                  child: Text(
                    _display(data.statusText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: _InfoLine(
                    label: 'Project / Office',
                    value: _display(data.projectName),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _InfoLine(
                    label: 'Items',
                    value: '${data.itemCount} item(s)',
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: _InfoLine(
                    label: 'Source',
                    value: _display(data.sourceLocationName),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _InfoLine(
                    label: 'Destination',
                    value: _display(data.destinationLocationName),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14.r,
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: 6.w),
                Text(
                  _display(data.movementDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (canOpen) ...[
                  const Spacer(),
                  Text(
                    'Open',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16.r,
                    color: AppColors.primary,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return const Color(0xFFB26A00);
      case 'submitted':
        return const Color(0xFF4B63E6);
      case 'issued':
        return const Color(0xFF159A61);
      case 'received':
        return const Color(0xFF00897B);
      default:
        return AppColors.textSecondary;
    }
  }

  String _display(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty || text.toLowerCase() == 'null') {
      return '-';
    }
    return text;
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const _InfoLine({
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
            fontSize: 11.sp,
            color: AppColors.textTertiary,
          ),
        ),
        SizedBox(height: 3.h),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
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

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(22.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 34.r, color: AppColors.textTertiary),
          SizedBox(height: 10.h),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

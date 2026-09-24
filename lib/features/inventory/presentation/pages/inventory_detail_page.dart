import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../../domain/entities/inventory_detail.dart';
import '../bloc/inventory_detail_bloc.dart';

class InventoryDetailPage extends StatelessWidget {
  final String inventoryId;
  final String? heroTag;

  const InventoryDetailPage({
    super.key,
    required this.inventoryId,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          sl<InventoryDetailBloc>()..add(LoadInventoryDetail(id: inventoryId)),
      child: Scaffold(
        backgroundColor: AppColors.lightBackground,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(context),
            SliverToBoxAdapter(
              child: BlocBuilder<InventoryDetailBloc, InventoryDetailState>(
                builder: (context, state) {
                  if (state is InventoryDetailLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (state is InventoryDetailLoaded) {
                    final InventoryDetail detail =
                        state.detail; // ✅ Explicit cast
                    return _buildContent(context, detail);
                  }

                  if (state is InventoryDetailError) {
                    return _buildError(context, state.message);
                  }

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
        //bottomNavigationBar: _buildBottomBar(context),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 300.h,
      pinned: true,
      backgroundColor: AppColors.primary,
      flexibleSpace: BlocBuilder<InventoryDetailBloc, InventoryDetailState>(
        builder: (context, state) {
          String? photoUrl;
          if (state is InventoryDetailLoaded) {
            photoUrl = state.detail.photo;
          }

          return FlexibleSpaceBar(
            background: Hero(
              tag: heroTag ?? 'inventory_$inventoryId',
              child: Container(
                color: Colors.grey[200],
                child: photoUrl != null && photoUrl.isNotEmpty
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            // Navigate to edit page
          },
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            _showOptionsMenu(context);
          },
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.primary.withOpacity(0.1),
      child: Center(
        child: Icon(
          Icons.inventory_2,
          size: 80.r,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, InventoryDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderInfo(detail),
        _buildInfoSection('Basic Information', [
          _buildInfoRow('Asset Code', detail.assetCode),
          _buildInfoRow('Brand', detail.brand ?? '-'),
          _buildInfoRow('Model', detail.model ?? '-'),
          _buildInfoRow('Serial Number', detail.sn ?? '-'),
          _buildInfoRow('Category', detail.categoryName ?? detail.group ?? '-'),
        ]),
        _buildInfoSection('Location & Usage', [
          _buildInfoRow(
              'Department', detail.departmentName ?? detail.department ?? '-'),
          _buildInfoRow(
              'Location', detail.locationName ?? detail.location ?? '-'),
          _buildInfoRow('Usage', detail.usage ?? '-'),
        ]),
        _buildInfoSection('Condition & Remarks', [
          _buildStatusRow('Condition', detail.condition ?? 'Unknown'),
          _buildInfoRow('Remarks', detail.remarks ?? '-'),
        ]),
        if (detail.history.isNotEmpty) _buildHistorySection(detail.history),
        if (detail.maintenance.isNotEmpty)
          _buildMaintenanceSection(detail.maintenance),
        if (detail.documents.isNotEmpty)
          _buildDocumentsSection(detail.documents),
        SizedBox(height: 20.h),
      ],
    );
  }

  Widget _buildHeaderInfo(InventoryDetail detail) {
    return Container(
      padding: EdgeInsets.all(16.w),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  detail.assetCode,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _buildStatusBadge(detail.condition ?? 'Unknown'),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            '${detail.brand ?? '-'} • ${detail.model ?? '-'}',
            style: TextStyle(
              fontSize: 16.sp,
              color: AppColors.textSecondary,
            ),
          ),
          if (detail.sn != null && detail.sn!.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              'SN: ${detail.sn}',
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'good':
      case 'available':
        return AppColors.success;
      case 'in use':
      case 'fair':
        return AppColors.warning;
      case 'damaged':
      case 'broken':
        return AppColors.error;
      case 'on board':
        return AppColors.info;
      default:
        return AppColors.textTertiary;
    }
  }

  Widget _buildInfoSection(String title, List<Widget> children) {
    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.all(16.w),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 12.h),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String status) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          SizedBox(
            width: 120.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          _buildStatusBadge(status),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<InventoryHistory> history) {
    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.all(16.w),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Movement History',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${history.length} records',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: history.length > 5 ? 5 : history.length,
            separatorBuilder: (context, index) => Divider(height: 1.h),
            itemBuilder: (context, index) {
              final item = history[index];
              return _buildHistoryItem(item);
            },
          ),
          if (history.length > 5)
            TextButton(
              onPressed: () {
                // Show all history
              },
              child: const Text('View All History'),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(InventoryHistory item) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.swap_horiz,
              color: AppColors.primary,
              size: 20.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.action,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.oldLocationName != null ||
                    item.newLocationName != null)
                  Text(
                    '${item.oldLocationName ?? '-'} → ${item.newLocationName ?? '-'}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                  ),
                Text(
                  '${item.userName ?? 'System'} • ${_formatDate(item.createdAt)}',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceSection(List<MaintenanceRecord> maintenance) {
    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.all(16.w),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Maintenance Records',
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${maintenance.length} records',
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: maintenance.length > 3 ? 3 : maintenance.length,
            separatorBuilder: (context, index) => Divider(height: 1.h),
            itemBuilder: (context, index) {
              final item = maintenance[index];
              return _buildMaintenanceItem(item);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceItem(MaintenanceRecord item) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.build,
              color: AppColors.warning,
              size: 20.r,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.type,
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (item.description != null)
                  Text(
                    item.description!,
                    style: TextStyle(
                      fontSize: 12.sp,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  '${item.technicianName ?? 'Unknown'} • ${_formatDate(item.maintenanceDate)}',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (item.cost != null)
            Text(
              '\$${item.cost!.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection(List<DocumentFile> documents) {
    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.all(16.w),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Documents',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: documents.map((doc) => _buildDocumentChip(doc)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentChip(DocumentFile doc) {
    IconData iconData;
    Color color;

    switch (doc.fileType.toLowerCase()) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        color = Colors.red;
        break;
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        color = Colors.blue;
        break;
      case 'xls':
      case 'xlsx':
        iconData = Icons.table_chart;
        color = Colors.green;
        break;
      case 'jpg':
      case 'jpeg':
      case 'png':
        iconData = Icons.image;
        color = Colors.purple;
        break;
      default:
        iconData = Icons.insert_drive_file;
        color = Colors.grey;
    }

    return ActionChip(
      avatar: Icon(iconData, color: color, size: 18.r),
      label: Text(
        doc.fileName,
        style: TextStyle(fontSize: 12.sp),
      ),
      onPressed: () {
        // Open document
      },
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 64.r,
              color: AppColors.error,
            ),
            SizedBox(height: 16.h),
            Text(
              'Failed to load detail',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.sp,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: () {
                context.read<InventoryDetailBloc>().add(
                      LoadInventoryDetail(id: inventoryId),
                    );
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // Share
                },
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Edit
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Equipment'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('MMM dd, yyyy').format(date);
  }

  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code),
              title: const Text('Show QR Code'),
              onTap: () {
                Navigator.pop(context);
                // Show QR
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('View Full History'),
              onTap: () {
                Navigator.pop(context);
                // Navigate to history
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Print Label'),
              onTap: () {
                Navigator.pop(context);
                // Print
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                // Confirm delete
              },
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../../config/constants.dart';
import '../../../../config/dependency_injection.dart';
import '../bloc/inventory_bloc.dart';
import '../../domain/entities/inventory.dart';  // ✅ TAMBAHKAN INI
import 'inventory_detail_page.dart';  // ✅ TAMBAHKAN INI

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  String _selectedCategory = 'Semua';

  final List<String> _categories = [
    'Semua',
    'Electronics',
    'Machinery',
    'Vehicle',
    'Tools',
  ];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => sl<InventoryBloc>()..add(const LoadInventory()),
      child: Scaffold(
        backgroundColor: AppColors.lightBackground,
        extendBody: true, 
        appBar: AppBar(
          title: const Text('Inventory'),
          backgroundColor: AppColors.lightBackground,
          elevation: 0,
          actions: [
          // Hanya search icon, add dihapus sementara
          IconButton(
            icon: Icon(Icons.search, size: 24.r),
            onPressed: () {
              // Focus ke search field
            },
          ),
          SizedBox(width: 8.w),
        ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            _buildCategoryFilter(),
            Expanded(child: _buildInventoryList()),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'inventory_page_fab',
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Add'),
          backgroundColor: AppColors.primary,
        ),
      ),
    );
  }

Widget _buildSearchBar() {
  return Container(
    margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
    height: 44.h, // Fixed height
    child: TextField(
      decoration: InputDecoration(
        hintText: 'Cari equipment...',
        hintStyle: TextStyle(
          fontSize: 14.sp,
          color: AppColors.textTertiary,
        ),
        prefixIcon: Icon(Icons.search, size: 20.r, color: AppColors.textTertiary),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColors.primary, width: 1.w),
        ),
      ),
      style: TextStyle(fontSize: 14.sp),
    ),
  );
}
Widget _buildCategoryFilter() {
  return Container(
    height: 40.h, // Lebih pendek
    margin: EdgeInsets.symmetric(vertical: 8.h),
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        final isSelected = _selectedCategory == category;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedCategory = category;
            });
            context.read<InventoryBloc>().add(LoadInventory(
                category: category == 'Semua' ? null : category));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.only(right: 8.w),
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(
                color: isSelected ? AppColors.primary : Colors.grey[300]!,
                width: 1.w,
              ),
            ),
            child: Text(
              category,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    ),
  );
}
  Widget _buildInventoryList() {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        if (state is InventoryLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is InventoryLoaded) {
          return RefreshIndicator(
            onRefresh: () async {
              context.read<InventoryBloc>().add(RefreshInventory());
            },
            child: ListView.builder(
              padding: EdgeInsets.all(16.w),
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return _buildInventoryItem(item);
              },
            ),
          );
        } else if (state is InventoryError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${state.message}'),
                ElevatedButton(
                  onPressed: () {
                    context.read<InventoryBloc>().add(const LoadInventory());
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

Widget _buildInventoryItem(Inventory item) {
  return GestureDetector(
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InventoryDetailPage(
            inventoryId: item.id,
            //heroTag: 'inventory_${item.id}_detail',
          ),
        ),
      );
    },
    child: Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Wrap image dengan Hero untuk animation
          Container(
            width: 60.w,
            height: 60.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: item.photo != null && item.photo!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: Image.network(
                      item.photo!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.image_not_supported,
                        color: AppColors.primary,
                        size: 30.r,
                      ),
                    ),
                  )
                : Icon(Icons.inventory_2, color: AppColors.primary, size: 30.r),
          ),

          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.assetCode,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  '${item.brand ?? '-'} • ${item.model ?? '-'}',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    _buildStatusBadge(_getStatusText(item.statusCode)),
                    SizedBox(width: 8.w),
                    Flexible(
                      child: Text(
                        item.sn ?? '',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 16.r,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    ),
  );
}
  String _getStatusText(int statusCode) {
    switch (statusCode) {
      case 1:
        return 'In Use';
      case 2:
        return 'Available';
      case 3:
        return 'On Board';
      default:
        return 'Unknown';
    }
  }

  Widget _buildStatusBadge(String status) {
    final color = status == 'Available'
        ? AppColors.success
        : status == 'In Use'
            ? AppColors.warning
            : AppColors.info;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

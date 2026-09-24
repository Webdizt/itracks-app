import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../config/constants.dart';
import '../../../../core/auth/app_auth_session.dart';
import '../../../dn/presentation/pages/dn_page.dart';

class ProjectPage extends StatefulWidget {
  const ProjectPage({Key? key}) : super(key: key);

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  late final Dio _dio;
  bool _loading = true;
  String? _error;
  List<ProjectSummary> _projects = const [];

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(baseUrl: AppConstants.baseUrl));
    _load();
  }

  Future<void> _setAuth() async {
    final token = await AppAuthSession.resolveApiBearerToken();
    _dio.options.headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _setAuth();
      final projectResponse = await _dio.get('/api/projects/list');
      final dnResponse = await _dio.get('/api/dn/list');

      final rawProjects = (projectResponse.data['data'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawDns = (dnResponse.data['data']?['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final dnCount = <String, int>{};
      final dnMap = <String, List<String>>{};
      for (final row in rawDns) {
        final key = '${row['job_number'] ?? ''}';
        if (key.isEmpty) continue;
        dnCount[key] = (dnCount[key] ?? 0) + 1;
        dnMap.putIfAbsent(key, () => []);
        dnMap[key]!.add('${row['dan_number'] ?? '-'}');
      }

      final items = rawProjects
          .map((row) => ProjectSummary.fromJson(
                row,
                dnCount['${row['job_number'] ?? ''}'] ?? 0,
                dnMap['${row['job_number'] ?? ''}'] ?? const [],
              ))
          .toList();

      setState(() {
        _projects = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ProjectCreatePage(projects: _projects)),
    );
    if (changed == true) {
      _load();
    }
  }

  void _openProject(ProjectSummary item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProjectDetailPage(project: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Project'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ProjectError(message: _error!, onRetry: _load)
              : ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 120.h),
                  children: [
                    Text(
                      'Setiap project terdiri dari beberapa DN.',
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    ..._projects.map(
                      (item) => GestureDetector(
                        onTap: () => _openProject(item),
                        child: Container(
                          margin: EdgeInsets.only(bottom: 12.h),
                          padding: EdgeInsets.all(16.w),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18.r),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadowLight,
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48.w,
                                height: 48.w,
                                decoration: BoxDecoration(
                                  color: AppColors.infoLight,
                                  borderRadius: BorderRadius.circular(14.r),
                                ),
                                child: const Icon(Icons.folder_open_rounded, color: AppColors.info),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.jobNumber,
                                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w800),
                                    ),
                                    SizedBox(height: 4.h),
                                    Text(
                                      item.client,
                                      style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 6.h),
                                    Wrap(
                                      spacing: 8.w,
                                      runSpacing: 8.h,
                                      children: [
                                        _projectChip('${item.dnCount} DN'),
                                        _projectChip(item.location.isEmpty ? 'No location' : item.location),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'project_list_fab',
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Add Project DN'),
      ),
    );
  }

  Widget _projectChip(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }
}

class ProjectCreatePage extends StatefulWidget {
  final List<ProjectSummary> projects;

  const ProjectCreatePage({
    Key? key,
    required this.projects,
  }) : super(key: key);

  @override
  State<ProjectCreatePage> createState() => _ProjectCreatePageState();
}

class _ProjectCreatePageState extends State<ProjectCreatePage> {
  ProjectSummary? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.projects.isNotEmpty) {
      _selected = widget.projects.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: const Text('Create Project DN')),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          _stepCard(
            number: 1,
            title: 'Select Project',
            child: DropdownButtonFormField<ProjectSummary>(
              value: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Project',
                prefixIcon: Icon(Icons.folder_open_outlined),
              ),
              items: widget.projects
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text('${item.jobNumber} • ${item.client}', overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selected = value),
            ),
          ),
          SizedBox(height: 12.h),
          _stepCard(
            number: 2,
            title: 'Add Box',
            child: Text(
              'After selecting a project, continue with box creation using the Delivery Note flow.',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(height: 12.h),
          _stepCard(
            number: 3,
            title: 'Add Item',
            child: Text(
              'Add items by scanning a QR code or entering them manually in the selected box.',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(height: 12.h),
          _stepCard(
            number: 4,
            title: 'Add Address',
            child: Text(
              'Tahap akhir isi sender dan delivery address sebelum dispatch.',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(height: 24.h),
          ElevatedButton.icon(
            onPressed: _selected == null
                ? null
                : () async {
                    final changed = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DnCreatePage(
                          presetType: 'project',
                          presetJobNumber: _selected!.jobNumber,
                        ),
                      ),
                    );
                    if (!mounted) return;
                    Navigator.pop(context, changed ?? true);
                  },
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Lanjut Buat DN Project'),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required int number,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$number. $title', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }
}

class ProjectDetailPage extends StatelessWidget {
  final ProjectSummary project;

  const ProjectDetailPage({
    Key? key,
    required this.project,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      appBar: AppBar(title: Text(project.jobNumber)),
      body: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          Container(
            padding: EdgeInsets.all(18.w),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.client, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800)),
                SizedBox(height: 6.h),
                Text(
                  project.location.isEmpty ? 'No location' : project.location,
                  style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                ),
                SizedBox(height: 12.h),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: AppColors.infoLight,
                    borderRadius: BorderRadius.circular(999.r),
                  ),
                  child: Text(
                    'Total DN: ${project.dnCount}',
                    style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.info),
                  ),
                ),
                if (project.dnNumbers.isNotEmpty) ...[
                  SizedBox(height: 16.h),
                  Text('Daftar DN', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 10.h),
                  ...project.dnNumbers.map(
                    (dn) => Container(
                      width: double.infinity,
                      margin: EdgeInsets.only(bottom: 8.h),
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        dn,
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'Projects use the Delivery Note workflow. Create a DN for this project, then select the project, add boxes, add items, and add addresses.',
            style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'project_detail_fab',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DnCreatePage(
                presetType: 'project',
                presetJobNumber: project.jobNumber,
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add DN'),
      ),
    );
  }
}

class ProjectSummary {
  final String jobNumber;
  final String client;
  final String location;
  final int dnCount;
  final List<String> dnNumbers;

  const ProjectSummary({
    required this.jobNumber,
    required this.client,
    required this.location,
    required this.dnCount,
    required this.dnNumbers,
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> json, int dnCount, List<String> dnNumbers) {
    return ProjectSummary(
      jobNumber: '${json['job_number'] ?? '-'}',
      client: '${json['client'] ?? json['company_name'] ?? '-'}',
      location: '${json['location'] ?? ''}',
      dnCount: dnCount,
      dnNumbers: dnNumbers,
    );
  }
}

class _ProjectError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProjectError({
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
            const Icon(Icons.error_outline, color: AppColors.error),
            SizedBox(height: 10.h),
            Text(message, textAlign: TextAlign.center),
            SizedBox(height: 12.h),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

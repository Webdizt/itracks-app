import 'dart:convert';

class QrScanResult {
  final String assetCode;
  final String assetName;
  final String sn;
  final String department;
  final String location;

  const QrScanResult({
    required this.assetCode,
    this.assetName = '',
    required this.sn,
    required this.department,
    required this.location,
  });

  factory QrScanResult.fromRawData(String rawData) {
    final source = rawData.trim();
    final lines = source.split(RegExp(r'[\r\n]+'));

    String assetCode = '';
    String assetName = '';
    String sn = '';
    String department = '';
    String location = '';

    final json = _decodeJsonObject(source);
    if (json != null) {
      assetCode = _firstJsonValue(json, const [
        'asset_code',
        'assetCode',
        'code',
        'asset_number',
        'assetNumber',
        'nomor_asset',
        'number',
      ]);
      assetName = _firstJsonValue(json, const [
        'asset_name',
        'assetName',
        'equipment_name',
        'equipmentName',
        'name',
      ]);
      sn = _firstJsonValue(json, const [
        'sn',
        'serial_number',
        'serialNumber',
      ]);
      department =
          _firstJsonValue(json, const ['department', 'department_name']);
      location = _firstJsonValue(json, const ['location', 'location_name']);
    }

    final uri = Uri.tryParse(source);
    if (uri != null && uri.hasScheme) {
      assetCode = assetCode.isNotEmpty
          ? assetCode
          : _firstUriValue(uri, const [
              'asset_code',
              'assetCode',
              'asset',
              'code',
              'number',
              'id',
            ]);
      sn = sn.isNotEmpty
          ? sn
          : _firstUriValue(uri, const ['sn', 'serial', 'serial_number']);
      if (assetCode.isEmpty && uri.pathSegments.isNotEmpty) {
        assetCode = Uri.decodeComponent(uri.pathSegments.last).trim();
      }
    }

    final unlabelled = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();

      final value = _labelValue(trimmed);
      if (RegExp(r'^(SN|SERIAL(?:\s+NUMBER)?)\s*[:=]', caseSensitive: false)
          .hasMatch(trimmed)) {
        sn = value;
      } else if (RegExp(
        r'^(ASSET\s*(?:CODE|NO|NUMBER)?|KODE\s*ASSET|NOMOR\s*ASSET)\s*[:=]',
        caseSensitive: false,
      ).hasMatch(trimmed)) {
        assetCode = value;
      } else if (RegExp(
        r'^(ASSET\s*NAME|NAMA\s*(?:ALAT|ASSET)|EQUIPMENT\s*NAME)\s*[:=]',
        caseSensitive: false,
      ).hasMatch(trimmed)) {
        assetName = value;
      } else if (trimmed.toLowerCase().startsWith('asset of')) {
        department = trimmed
            .replaceFirst(RegExp(r'^Asset of\s*', caseSensitive: false), '')
            .trim();
      } else if (trimmed.isNotEmpty &&
          !trimmed.contains(':') &&
          !trimmed.contains('=') &&
          json == null &&
          !(uri?.hasScheme ?? false)) {
        unlabelled.add(trimmed);
      }
    }

    if (assetCode.isEmpty && unlabelled.isNotEmpty) {
      assetCode = unlabelled.first;
    }

    if (assetCode.isNotEmpty) {
      final parsed = _QrAssetCodeParser.parse(assetCode);
      department = department.isNotEmpty ? department : parsed.department;
      location = parsed.location;
    }

    return QrScanResult(
      assetCode: assetCode,
      assetName: assetName,
      sn: sn,
      department: department,
      location: location,
    );
  }

  bool get isValid => assetCode.isNotEmpty;

  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    if (!(raw.startsWith('{') && raw.endsWith('}'))) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static String _firstJsonValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = '${json[key] ?? ''}'.trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  static String _firstUriValue(Uri uri, List<String> keys) {
    for (final key in keys) {
      final value = (uri.queryParameters[key] ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _labelValue(String line) {
    final separator = line.indexOf(RegExp(r'[:=]'));
    return separator < 0 ? '' : line.substring(separator + 1).trim();
  }
}

class _QrAssetCodeMetadata {
  final String department;
  final String location;

  const _QrAssetCodeMetadata({
    required this.department,
    required this.location,
  });
}

class _QrAssetCodeParser {
  static const Map<String, String> _departmentMap = {
    '01': 'Survey',
    '02': 'Inspection',
    '03': 'ROV',
    '04': 'Diving',
    '06': 'IT',
    '07': 'HSE',
    '08': 'Finance',
    '09': 'Tax',
    '10': 'Tender',
    '11': 'Workshop',
    '12': 'HR',
    '13': 'Balikpapan / Batam',
    '14': 'Operations',
    '15': 'Purchasing',
    '16': 'Subsea',
    '17': 'Quisea',
  };

  static const Map<String, String> _locationMap = {
    '01': 'Office',
    '02': 'Field',
    '03': 'Balikpapan',
    '04': 'Batam',
  };

  static _QrAssetCodeMetadata parse(String rawAssetCode) {
    final assetCode = rawAssetCode.trim().toUpperCase();
    String departmentCode = '';
    String locationCode = '';

    final hyphenMatch =
        RegExp(r'^SSI-[A-Z]+-(\d{2})(\d{2})-').firstMatch(assetCode);
    if (hyphenMatch != null) {
      departmentCode = hyphenMatch.group(1) ?? '';
      locationCode = hyphenMatch.group(2) ?? '';
    } else {
      final compact = assetCode.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      final compactMatch =
          RegExp(r'^SSI[A-Z]{0,2}(\d{2})(\d{2})').firstMatch(compact);
      if (compactMatch != null) {
        departmentCode = compactMatch.group(1) ?? '';
        locationCode = compactMatch.group(2) ?? '';
      }
    }

    return _QrAssetCodeMetadata(
      department: _departmentMap[departmentCode] ?? '',
      location: _locationMap[locationCode] ?? '',
    );
  }
}

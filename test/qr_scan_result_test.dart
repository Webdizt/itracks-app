import 'package:flutter_test/flutter_test.dart';
import 'package:itracks_app/features/inventory/domain/entities/qr_scan_result.dart';

void main() {
  group('QrScanResult', () {
    test('membaca label aset lama tanpa menimpa kode dengan nama alat', () {
      final result = QrScanResult.fromRawData('''
Asset Code: SSI-IT-0601-0012
Nama Alat: Laptop Dell Latitude
SN: DL-99881
Asset of IT
''');

      expect(result.assetCode, 'SSI-IT-0601-0012');
      expect(result.assetName, 'Laptop Dell Latitude');
      expect(result.sn, 'DL-99881');
      expect(result.department, 'IT');
      expect(result.location, 'Office');
    });

    test('membaca QR versi dua yang hanya berisi nomor', () {
      final result = QrScanResult.fromRawData('00001234');

      expect(result.assetCode, '00001234');
      expect(result.assetName, isEmpty);
      expect(result.sn, isEmpty);
      expect(result.isValid, isTrue);
    });

    test('membaca payload JSON dan URL aset', () {
      final jsonResult = QrScanResult.fromRawData(
        '{"asset_code":"SSI-IT-0601-0013","asset_name":"ROV Laptop","sn":"SN-13"}',
      );
      final urlResult = QrScanResult.fromRawData(
        'https://itrack.example/assets/detail?asset_code=SSI-IT-0601-0014&sn=SN-14',
      );

      expect(jsonResult.assetCode, 'SSI-IT-0601-0013');
      expect(jsonResult.assetName, 'ROV Laptop');
      expect(jsonResult.sn, 'SN-13');
      expect(urlResult.assetCode, 'SSI-IT-0601-0014');
      expect(urlResult.sn, 'SN-14');
    });
  });
}

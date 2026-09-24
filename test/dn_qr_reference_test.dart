import 'package:flutter_test/flutter_test.dart';
import 'package:itracks_app/features/dn/presentation/pages/dn_page.dart';

void main() {
  test('QR URL PDF DN mengambil UUID sebelum segmen detail', () {
    expect(
      dnIdentifierFromQr(
        'http://10.84.19.221:5000/delivery-note/outgoing/'
        '0ee6f535ac8e4d858fc12c65903c938a/detail',
      ),
      '0ee6f535ac8e4d858fc12c65903c938a',
    );
  });

  test('QR DN tetap menerima UUID mentah dan query parameter', () {
    expect(
      dnIdentifierFromQr('0ee6f535ac8e4d858fc12c65903c938a'),
      '0ee6f535ac8e4d858fc12c65903c938a',
    );
    expect(
      dnIdentifierFromQr(
        'https://example.test/scan?uuid=0ee6f535ac8e4d858fc12c65903c938a',
      ),
      '0ee6f535ac8e4d858fc12c65903c938a',
    );
  });
}

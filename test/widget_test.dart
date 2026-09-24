import 'package:flutter_test/flutter_test.dart';
import 'package:itracks_app/features/dn/presentation/pages/dn_page.dart';
import 'package:itracks_app/features/auth/presentation/pages/login_page.dart';

void main() {
  test('basic sanity check', () {
    expect(true, isTrue);
  });

  test('incoming DN pages are available', () {
    expect(const DnIncomingPage(), isA<DnIncomingPage>());
  });

  test('login page is available', () {
    expect(const LoginPage(), isA<LoginPage>());
  });
}

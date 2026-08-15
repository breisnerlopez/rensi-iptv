import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rensi_iptv/utils/connectivity_helper.dart';

void main() {
  group('ConnectivityHelper.cellularOnly', () {
    test('solo celular → true', () {
      expect(ConnectivityHelper.cellularOnly([ConnectivityResult.mobile]),
          isTrue);
    });

    test('Wi‑Fi → false', () {
      expect(ConnectivityHelper.cellularOnly([ConnectivityResult.wifi]),
          isFalse);
    });

    test('Ethernet → false', () {
      expect(ConnectivityHelper.cellularOnly([ConnectivityResult.ethernet]),
          isFalse);
    });

    test('celular + Wi‑Fi (ambiguo) → false, nunca oculta cast', () {
      expect(
        ConnectivityHelper.cellularOnly(
            [ConnectivityResult.mobile, ConnectivityResult.wifi]),
        isFalse,
      );
    });

    test('celular + VPN (ambiguo) → false', () {
      expect(
        ConnectivityHelper.cellularOnly(
            [ConnectivityResult.mobile, ConnectivityResult.vpn]),
        isFalse,
      );
    });

    test('lista vacía → false (no asumir celular ante desconocido)', () {
      expect(ConnectivityHelper.cellularOnly(const []), isFalse);
    });

    test('none → false', () {
      expect(ConnectivityHelper.cellularOnly([ConnectivityResult.none]),
          isFalse);
    });
  });
}

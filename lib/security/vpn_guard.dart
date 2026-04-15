import 'dart:io';

class VpnGuard {
  static const List<String> _vpnHints = <String>[
    'tun',
    'tap',
    'ppp',
    'ipsec',
    'utun',
    'wg', // wireguard
    'wireguard',
  ];

  static Future<bool> isVpnActive() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      final ifaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      for (final iface in ifaces) {
        final name = iface.name.toLowerCase();
        for (final hint in _vpnHints) {
          if (name.contains(hint)) return true;
        }
      }
      return false;
    } catch (_) {
      // Fail open to avoid false-locking users due to platform restrictions.
      return false;
    }
  }
}

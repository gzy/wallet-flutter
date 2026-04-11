import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 6 位数字 PIN：仅存 salt + SHA-256 摘要（不存明文）
class PinCrypto {
  PinCrypto._();

  static String randomSalt() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(b);
  }

  static String hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt$pin');
    return sha256.convert(bytes).toString();
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path_provider/path_provider.dart';

/// 将助记词用备份密码加密后写入应用文档目录（不上传 iCloud）
class LocalBackupService {
  LocalBackupService._();

  static List<int> _deriveKeyBytes(String password, String salt) {
    final merged = utf8.encode('$salt$password');
    return sha256.convert(merged).bytes;
  }

  static String _randomSalt() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// 返回生成的备份文件路径；内容为 JSON：salt、iv、cipher（Base64）
  static Future<String> writeEncryptedBackup({
    required String mnemonic,
    required String backupPassword,
    required String walletId,
  }) async {
    final salt = _randomSalt();
    final keyBytes = _deriveKeyBytes(backupPassword, salt);
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(mnemonic.trim(), iv: iv);

    final payload = <String, dynamic>{
      'v': 1,
      'walletId': walletId,
      'salt': salt,
      'iv': base64Encode(iv.bytes),
      'cipher': encrypted.base64,
    };
    final dir = await getApplicationDocumentsDirectory();
    final name = 'wallet_backup_${walletId.substring(0, 8)}.json';
    final file = File('${dir.path}/$name');
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }

  /// 解密 [writeEncryptedBackup] 生成的 JSON 文本，返回助记词字符串。
  static String decryptLocalBackup(String jsonContent, String backupPassword) {
    final map = jsonDecode(jsonContent) as Map<String, dynamic>;
    final v = map['v'];
    if (v != 1) {
      throw FormatException('不支持的备份版本: $v');
    }
    final salt = map['salt'] as String?;
    final ivB64 = map['iv'] as String?;
    final cipherB64 = map['cipher'] as String?;
    if (salt == null || ivB64 == null || cipherB64 == null) {
      throw const FormatException('备份文件字段不完整');
    }
    final keyBytes = _deriveKeyBytes(backupPassword, salt);
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV.fromBase64(ivB64);
    final encrypted = enc.Encrypted.fromBase64(cipherB64);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return encrypter.decrypt(encrypted, iv: iv);
  }
}

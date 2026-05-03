import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:web3dart/crypto.dart';

/// XRPL Classic 收款地址用的 Ripple Base58 字母表（与 Bitcoin 不同）。
const _rippleB58Alphabet =
    'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz';

Uint8List _rippleSha256Once(Uint8List input) =>
    Uint8List.fromList(sha256.convert(input).bytes);

Uint8List _rippleSha256d(Uint8List input) =>
    _rippleSha256Once(_rippleSha256Once(input));

/// 压缩格式 33 字节公钥前缀 `02`/`03`。XRPL Classic 账户 ID：`RMD160(SHA256(压缩公钥))`。
Uint8List secp256k1CompressPublicKeyFromXy64(Uint8List xy64) {
  if (xy64.length != 64) {
    throw ArgumentError.value(xy64.length, 'xy64.length', 'expected 64');
  }
  var yi = BigInt.zero;
  for (final b in xy64.sublist(32, 64)) {
    yi = (yi << 8) + BigInt.from(b);
  }
  final prefix = yi.isOdd ? 0x03 : 0x02;
  return Uint8List.fromList([prefix, ...xy64.sublist(0, 32)]);
}

Uint8List _rippleHash160(Uint8List input) {
  final shaOut = _rippleSha256Once(input);
  final d = RIPEMD160Digest();
  final out = Uint8List(d.digestSize);
  d.update(shaOut, 0, shaOut.length);
  d.doFinal(out, 0);
  return out;
}

Uint8List? _rippleB58DecodeRaw(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  var num = BigInt.zero;
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final p = _rippleB58Alphabet.indexOf(ch);
    if (p < 0) {
      return null;
    }
    num = num * BigInt.from(58) + BigInt.from(p);
  }
  final bytes = <int>[];
  while (num > BigInt.zero) {
    final mod = (num & BigInt.from(0xff)).toInt();
    bytes.add(mod);
    num = num >> 8;
  }
  final ordered = bytes.reversed.toList();

  var leading = 0;
  for (var i = 0; i < s.length && s[i] == _rippleB58Alphabet[0]; i++) {
    leading++;
  }
  if (leading > 0) {
    ordered.insertAll(0, List<int>.filled(leading, 0));
  }
  return Uint8List.fromList(ordered);
}

String _rippleB58Encode(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  var num = BigInt.zero;
  for (final b in bytes) {
    num = (num << 8) + BigInt.from(b);
  }
  final chars = <String>[];
  while (num > BigInt.zero) {
    final mod = (num % BigInt.from(58)).toInt();
    chars.add(_rippleB58Alphabet[mod]);
    num = num ~/ BigInt.from(58);
  }
  final ordered = chars.reversed.toList();

  var leadingZeros = 0;
  for (final b in bytes) {
    if (b == 0) {
      leadingZeros++;
    } else {
      break;
    }
  }
  if (leadingZeros > 0) {
    return (_rippleB58Alphabet[0] * leadingZeros) + ordered.join();
  }
  return ordered.join();
}

String rippleClassicAddressEncodeFromAccountIdBytes(Uint8List accountId20) {
  if (accountId20.length != 20) {
    throw ArgumentError.value(accountId20.length, 'len', 'expected 20');
  }
  final payload = Uint8List(21);
  payload[0] = 0x00;
  payload.setRange(1, 21, accountId20);
  final checksum = _rippleSha256d(payload).sublist(0, 4);
  final all = Uint8List(25);
  all.setRange(0, 21, payload);
  all.setRange(21, 25, checksum);
  return _rippleB58Encode(all);
}

/// 从 32 字节 secp256k1 私钥派生 Classic `r...` 地址（与 ripple-keypairs / Ledger BIP44 一致）。
String xrpAddressFromPrivateKeyBytes(Uint8List privateKey32) {
  final xy = privateKeyBytesToPublic(privateKey32);
  final compressed = secp256k1CompressPublicKeyFromXy64(xy);
  final h160 = _rippleHash160(compressed);
  return rippleClassicAddressEncodeFromAccountIdBytes(h160);
}

/// 校验 XRPL Classic 地址格式与校验和（大小写敏感，勿 lower-case）。
bool isValidXrpClassicAddress(String raw) {
  final s = raw.trim();
  if (s.isEmpty || !s.startsWith('r')) {
    return false;
  }
  final decoded = _rippleB58DecodeRaw(s);
  if (decoded == null || decoded.length != 25) {
    return false;
  }
  if (decoded[0] != 0x00) {
    return false;
  }
  final payload = decoded.sublist(0, 21);
  final checksum = decoded.sublist(21);
  final expected = _rippleSha256d(payload).sublist(0, 4);
  for (var i = 0; i < 4; i++) {
    if (checksum[i] != expected[i]) return false;
  }
  return true;
}

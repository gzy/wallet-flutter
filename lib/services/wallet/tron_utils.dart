import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web3dart/crypto.dart';

const _b58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

Uint8List _sha256(Uint8List input) =>
    Uint8List.fromList(sha256.convert(input).bytes);

Uint8List _sha256d(Uint8List input) => _sha256(_sha256(input));

Uint8List _b58Decode(String s) {
  final input = s.trim();
  if (input.isEmpty) return Uint8List(0);
  BigInt num = BigInt.zero;
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final p = _b58Alphabet.indexOf(ch);
    if (p < 0) {
      throw const FormatException('invalid base58 character');
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

  // handle leading zeros
  var leadingOnes = 0;
  for (var i = 0; i < input.length && input[i] == '1'; i++) {
    leadingOnes++;
  }
  if (leadingOnes > 0) {
    ordered.insertAll(0, List<int>.filled(leadingOnes, 0));
  }
  return Uint8List.fromList(ordered);
}

String _b58Encode(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  BigInt num = BigInt.zero;
  for (final b in bytes) {
    num = (num << 8) + BigInt.from(b);
  }
  final chars = <String>[];
  while (num > BigInt.zero) {
    final mod = (num % BigInt.from(58)).toInt();
    chars.add(_b58Alphabet[mod]);
    num = num ~/ BigInt.from(58);
  }
  final ordered = chars.reversed.toList();

  // leading zeros => '1'
  var leadingZeros = 0;
  for (final b in bytes) {
    if (b == 0) {
      leadingZeros++;
    } else {
      break;
    }
  }
  if (leadingZeros > 0) {
    return ('1' * leadingZeros) + ordered.join();
  }
  return ordered.join();
}

/// 校验 Tron Base58Check 地址（T...）。
bool isValidTronAddress(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return false;
  try {
    final decoded = _b58Decode(s);
    if (decoded.length != 25) return false;
    final payload = decoded.sublist(0, 21);
    final checksum = decoded.sublist(21);
    final expected = _sha256d(Uint8List.fromList(payload)).sublist(0, 4);
    for (var i = 0; i < 4; i++) {
      if (checksum[i] != expected[i]) return false;
    }
    // Tron mainnet/testnet address prefix 0x41
    return payload[0] == 0x41;
  } catch (_) {
    return false;
  }
}

/// 从私钥 bytes 派生 Tron 地址（Base58Check，T...）。
String tronAddressFromPrivateKeyBytes(Uint8List privateKey32) {
  final pub = privateKeyBytesToPublic(privateKey32);
  // web3dart 的 privateKeyBytesToPublic 已经返回 64 字节（去掉了 0x04 前缀），这里不能再 sublist(1)。
  final hash = keccak256(pub);
  final addr20 = hash.sublist(12);
  final payload = Uint8List(21);
  payload[0] = 0x41;
  payload.setRange(1, 21, addr20);
  final checksum = _sha256d(payload).sublist(0, 4);
  final all = Uint8List(payload.length + checksum.length);
  all.setRange(0, payload.length, payload);
  all.setRange(payload.length, all.length, checksum);
  return _b58Encode(all);
}

Uint8List tronHexToBytes(String hex) {
  final s = hex.trim();
  if (s.isEmpty) return Uint8List(0);
  return hexToBytes(s.startsWith('0x') ? s.substring(2) : s);
}


import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:web3dart/crypto.dart' show bytesToHex, sign;

import 'tron_utils.dart';

/// TRON 待签交易签名结果。
class TronSignedTransaction {
  const TronSignedTransaction({
    required this.txMap,
    required this.signedJson,
    required this.signatureHex,
  });

  final Map<String, dynamic> txMap;
  final String signedJson;
  final String signatureHex;
}

/// 对后端返回的 TRON 未签交易（createTransaction / preorder）做本地 ECDSA 签名。
abstract final class TronTransactionSigner {
  TronTransactionSigner._();

  static String? extractRawDataHex(Map<String, dynamic> data) {
    final raw = data['rawDataHex'] ??
        data['raw_data_hex'] ??
        (data['transaction'] is Map
            ? (data['transaction'] as Map)['raw_data_hex'] ??
                (data['transaction'] as Map)['rawDataHex']
            : null);
    final s = raw?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static Map<String, dynamic> transactionMapFromData(Map<String, dynamic> data) {
    final tx = data['transaction'];
    if (tx is Map) {
      return Map<String, dynamic>.from(tx);
    }
    return Map<String, dynamic>.from(data);
  }

  static TronSignedTransaction signApiData(
    Map<String, dynamic> data,
    Uint8List privateKey,
  ) {
    final rawHex = extractRawDataHex(data);
    if (rawHex == null) {
      throw StateError('缺少 rawDataHex/raw_data_hex');
    }
    final rawBytes = tronHexToBytes(rawHex);
    final digest = sha256.convert(rawBytes).bytes;
    final sig = sign(Uint8List.fromList(digest), privateKey);
    final sigBytes = Uint8List(65);
    sigBytes.setRange(0, 32, _uint256To32(sig.r));
    sigBytes.setRange(32, 64, _uint256To32(sig.s));
    final recId = sig.v >= 27 ? (sig.v - 27) : sig.v;
    sigBytes[64] = recId;
    final sigHex = bytesToHex(sigBytes, include0x: false);

    final txMap = transactionMapFromData(data);
    txMap['signature'] = [sigHex];
    return TronSignedTransaction(
      txMap: txMap,
      signedJson: jsonEncode(txMap),
      signatureHex: sigHex,
    );
  }

  static Uint8List _uint256To32(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }
}

import 'dart:convert';

import 'package:web3dart/crypto.dart' show hexToBytes;
import 'package:xrpl_dart/xrpl_dart.dart';

import 'hd_wallet_service.dart';

/// 后端 `createTransaction` 返回未签名 XRPL 交易（JSON 或 **hex / base64 blob**），
/// 客户端用 BIP44 派生的 secp256k1 私钥签名后 `broadcastTransaction`（[data] 为 **base64** 与 Solana 一致）。
abstract final class XrpBackendTransfer {
  XrpBackendTransfer._();

  /// 与链上 JSON 混在同一 map 里时，不能参与 `fromXrpl`（否则会把 blob 误当字段解析，触发 Base58 异常）。
  static const _jsonNoiseKeys = {
    'blob',
    'txblob',
    'transactionblob',
    'unsignedblob',
    'unsignedtransactionhex',
    'code',
    'message',
    'msg',
    'success',
    'timestamp',
  };

  static const _blobFieldNames = [
    'unsignedTransactionHex',
    'txBlob',
    'transactionBlob',
    'unsignedBlob',
    'blob',
    'data',
    'txBase64',
  ];

  static XRPPrivateKey privateKeyFromMnemonic(String mnemonic) {
    final raw = HdWalletService.xrpPrivateKeyBytesFromMnemonic(mnemonic);
    return XRPPrivateKey.fromBytes(
      raw,
      algorithm: XRPKeyAlgorithm.secp256k1,
    );
  }

  static Map<String, dynamic> _stripJsonNoise(Map<String, dynamic> raw) {
    final out = Map<String, dynamic>.from(raw);
    for (final k in out.keys.toList()) {
      if (_jsonNoiseKeys.contains(k.toLowerCase())) {
        out.remove(k);
      }
    }
    return out;
  }

  static String _normRippleJsonKey(String k) =>
      k.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');

  /// IOU/MPT 等 **发币支付** 才可能需要 `Paths`；其余 Payment（含 drops 串、数字、带小数点的 XRP 表示等）一律剥掉 `Paths`，
  /// 避免 PathSet 里坏 `account`/`issuer` 触发 Base58 或长时间序列化。
  static bool _issuedPaymentProbablyNeedsRipplePaths(Object? amount) {
    if (amount is! Map) return false;
    final m = Map<String, dynamic>.from(amount);
    final cur = (m['currency'] ?? m['Currency'])?.toString().trim().toUpperCase();
    final issuerRaw = m['issuer'] ?? m['Issuer'];
    final issuer = issuerRaw?.toString().trim();
    final hasIssuer = issuer != null && issuer.isNotEmpty;
    final notNativeCur =
        cur != null && cur.isNotEmpty && cur != 'XRP';
    return hasIssuer || notNativeCur;
  }

  static Map<String, dynamic> _stripPathsUnlessIssuedCurrencyPayment(
      Map<String, dynamic> env) {
    final m = Map<String, dynamic>.from(env);
    final tt =
        (m['TransactionType'] ?? m['transaction_type'])?.toString() ?? '';
    if (tt.toLowerCase() != 'payment') return m;

    final amt = m['Amount'] ?? m['amount'];
    if (_issuedPaymentProbablyNeedsRipplePaths(amt)) return m;

    if (m.containsKey('Paths')) {
      m.remove('Paths');
    }
    if (m.containsKey('paths')) {
      m.remove('paths');
    }
    return m;
  }

  /// XRP Ledger JSON 中与 Base58 Codec 绑定的字段（序列化时会解码；含 BOM/空格会报错）。
  static bool _jsonValueIsRippleAddressField(String key, Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return false;
    }
    final nk = _normRippleJsonKey(key);
    return nk == 'account' ||
        nk == 'destination' ||
        nk == 'issuer' ||
        nk == 'authorize' ||
        nk == 'owner' ||
        nk == 'regularkey' ||
        nk == 'publisher' ||
        nk == 'nftokenowner' ||
        nk == 'nftokenissuer' ||
        nk == 'seller' ||
        nk == 'buyer' ||
        nk == 'taker' ||
        nk == 'authorizeaccount';
  }

  static String _sanitizeClassicAddressChars(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '');
    return s.trim();
  }

  /// 任意嵌套处形似 Classic `r...` 的字符串（含 Payment Paths、Amount issuer 等）。
  static bool _looksLikeRippleClassicShape(String raw) {
    final s = raw.trim();
    if (s.length < 25 || s.length > 36 || !s.startsWith('r')) {
      return false;
    }
    return true;
  }

  /// Ripple Classic 地址体部允许的 Base58 字符（不含前缀 `r`）。
  static bool _rippleClassicBodyCharValid(String ch) {
    return RegExp(r'^[1-9A-HJ-NP-Za-km-z]$').hasMatch(ch);
  }

  /// 在调用 `toSigningBlobBytes` 前先失败，避免调试器总在 `blockchain_utils` 的 Base58 里断住；
  /// 信息与后续 `catch` 中的包装一致指向「非法字符」。
  static void _precheckClassicRippleAddressOrThrow(String label, String raw) {
    final s = _sanitizeClassicAddressChars(raw);
    if (s.isEmpty) return;
    if (!_looksLikeRippleClassicShape(s)) return;
    for (var i = 1; i < s.length; i++) {
      final ch = s[i];
      if (!_rippleClassicBodyCharValid(ch)) {
        throw StateError(
          'XRP Classic 地址 [$label] 在第 $i 个字节处含非法 Ripple Base58 字符 (“$ch”）。'
          ' Ripple 字母表不包含 0、O、I、l；请核对网关或与剪贴板混淆的可视字符。',
        );
      }
    }
  }

  static void _precheckSigningAddresses(SubmittableTransaction tx) {
    _precheckClassicRippleAddressOrThrow('Account', tx.account);
    if (tx.transactionType != SubmittableTransactionType.payment) return;
    final p = tx.cast<Payment>();
    _precheckClassicRippleAddressOrThrow('Destination', p.destination);
    final amt = p.amount;
    if (amt is IssuedCurrencyAmount) {
      _precheckClassicRippleAddressOrThrow('Amount.issuer', amt.issuer);
    }
    final paths = p.paths;
    if (paths == null) return;
    for (var pi = 0; pi < paths.length; pi++) {
      for (var si = 0; si < paths[pi].length; si++) {
        final st = paths[pi][si];
        final a = st.account;
        if (a != null && a.isNotEmpty) {
          _precheckClassicRippleAddressOrThrow('Paths[$pi][$si].account', a);
        }
        final iss = st.issuer;
        if (iss != null && iss.isNotEmpty) {
          _precheckClassicRippleAddressOrThrow('Paths[$pi][$si].issuer', iss);
        }
      }
    }
  }

  /// 递归裁剪地址类字符串，降低 `toSigningBlobBytes` / `AccountID.fromValue` 内 Base58 解码失败概率。
  static dynamic _sanitizeRippledAddressStrings(dynamic node) {
    if (node is Map) {
      final m = Map<String, dynamic>.from(node);
      for (final e in m.entries.toList()) {
        final k = e.key.toString();
        final v = e.value;
        if (v is Map || v is List) {
          m[k] = _sanitizeRippledAddressStrings(v);
        } else if (v is String) {
          final trimmed = v.trim();
          final classicShape = _looksLikeRippleClassicShape(trimmed);
          if (classicShape || _jsonValueIsRippleAddressField(k, v)) {
            m[k] = _sanitizeClassicAddressChars(v);
          }
        }
      }
      return m;
    }
    if (node is List) {
      return node.map(_sanitizeRippledAddressStrings).toList();
    }
    return node;
  }

  static Map<String, dynamic> _cleanEnvelope(Map<String, dynamic> raw) {
    final stripped = _stripJsonNoise(raw);
    final out = _sanitizeRippledAddressStrings(stripped);
    return Map<String, dynamic>.from(out as Map);
  }

  /// 取出「纯交易 JSON」：嵌套 `transaction` / `tx_json` …，或与 blob 并排放在根级的交易字段。
  static Map<String, dynamic>? _transactionJsonEnvelope(
      Map<String, dynamic> data) {
    for (final k in [
      'transaction',
      'tx_json',
      'tx',
      'unsignedTransaction',
      'txn'
    ]) {
      final v = data[k];
      if (v is Map) {
        return _cleanEnvelope(Map<String, dynamic>.from(v));
      }
      if (v is String) {
        final t = v.trim();
        if (t.startsWith('{')) {
          try {
            final decoded = jsonDecode(t);
            if (decoded is Map) {
              return _cleanEnvelope(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
      }
    }
    if (data['TransactionType'] != null || data['transaction_type'] != null) {
      return _cleanEnvelope(Map<String, dynamic>.from(data));
    }
    return null;
  }

  static bool _looksLikeHex(String s) {
    var u = s.trim().replaceAll(RegExp(r'\s+'), '');
    if (u.isEmpty || u.length < 4 || u.length % 2 != 0) return false;
    if (u.startsWith('0x') || u.startsWith('0X')) {
      u = u.substring(2);
      if (u.length % 2 != 0) return false;
    }
    return RegExp(r'^[0-9A-Fa-f]+$').hasMatch(u);
  }

  static List<int>? _tryDecodeHexBytes(String raw) {
    if (!_looksLikeHex(raw)) return null;
    try {
      var t = raw.trim().replaceAll(RegExp(r'\s+'), '');
      if (t.startsWith('0x') || t.startsWith('0X')) {
        t = t.substring(2);
      }
      return hexToBytes('0x${t.toLowerCase()}');
    } catch (_) {
      return null;
    }
  }

  static List<int>? _tryDecodeBase64Bytes(String raw) {
    final t = raw.trim();
    if (t.length < 8) return null;
    if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(t)) return null;
    try {
      return base64Decode(t);
    } catch (_) {
      try {
        return base64Url.decode(t.normalizeBase64UrlPad());
      } catch (_) {
        return null;
      }
    }
  }

  /// 先试 hex，再试 base64 / base64url。
  static List<int>? _decodeBlobPayload(String raw) {
    return _tryDecodeHexBytes(raw) ?? _tryDecodeBase64Bytes(raw);
  }

  static SubmittableTransaction _parseUnsigned(Map<String, dynamic> data) {
    final env = _transactionJsonEnvelope(data);
    if (env != null) {
      final envSign = _stripPathsUnlessIssuedCurrencyPayment(env);
      try {
        return SubmittableTransaction.fromXrpl(envSign);
      } catch (_) {
        try {
          return SubmittableTransaction.fromJson(envSign);
        } catch (e) {
          throw StateError('XRPL 交易 JSON 解析失败（已剥离 blob 等字段）: $e');
        }
      }
    }

    for (final k in _blobFieldNames) {
      final v = data[k];
      if (v is! String) continue;
      final trimmed = v.trim();
      if (trimmed.isEmpty) continue;
      final bytes = _decodeBlobPayload(trimmed);
      if (bytes == null || bytes.isEmpty) continue;
      try {
        return SubmittableTransaction.fromBytes(bytes);
      } catch (_) {
        continue;
      }
    }

    throw StateError(
      'createTransaction 返回无可识别的 XRPL 未签数据（需要 transaction/tx_json 等 JSON，或 hex/base64 的 blob）',
    );
  }

  /// 返回 **base64(已签交易原始字节)**，供 [WalletTransferApiService.broadcastTransaction] 的 `data`。
  static String signCreateTransactionData({
    required Map<String, dynamic> data,
    required XRPPrivateKey privateKey,
    required String expectedOwnerClassicAddress,
  }) {
    final owner = expectedOwnerClassicAddress.trim();
    final derived = privateKey.getPublic().toAddress().toString();
    if (derived != owner) {
      throw StateError('XRP 派生地址与当前钱包展示地址不一致');
    }

    final tx = _parseUnsigned(data);
    final acct = _sanitizeClassicAddressChars(tx.account);
    final ownerSan = _sanitizeClassicAddressChars(owner);
    if (acct != ownerSan) {
      throw StateError('交易 Account 与付款地址不一致');
    }

    final pubHex = privateKey.getPublic().toHex();
    final existing = tx.signer;
    if (existing == null || existing.signingPubKey.isEmpty) {
      tx.setSignature(XRPLSignature.signer(pubHex));
    } else if (existing.signingPubKey.toUpperCase() != pubHex.toUpperCase()) {
      throw StateError('交易 SigningPubKey 与当前钱包公钥不一致');
    }

    final signerAddr = privateKey.getPublic().toAddress();
    _precheckSigningAddresses(tx);
    final List<int> blob;
    try {
      blob = tx.toSigningBlobBytes(signerAddr);
    } catch (e) {
      final m = '$e';
      if (m.contains('Invalid character in Base58') ||
          m.contains('MessageException')) {
        throw StateError(
          'XRPL 交易序列化失败：某 Classic 地址字段仍含非法 Base58 字符'
          '（多为 Destination / Issuer / Path.account，或网关返回里夹带不可见字符）。'
          ' 原始异常: $m',
        );
      }
      rethrow;
    }
    final sig = privateKey.sign(blob);
    tx.setSignature(sig);

    final hexBlob = tx.toTransactionBlob();
    var h = hexBlob.trim();
    if (h.startsWith('0x') || h.startsWith('0X')) {
      h = h.substring(2);
    }
    final raw = hexToBytes('0x${h.toLowerCase()}');
    final outB64 = base64Encode(raw);
    return outB64;
  }
}

extension on String {
  /// `base64Url` decode 时对 padding 做宽松处理。
  String normalizeBase64UrlPad() {
    var s = trim();
    final pad = s.length % 4;
    if (pad != 0) {
      s = s.padRight(s.length + (4 - pad), '=');
    }
    return s;
  }
}

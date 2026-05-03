import 'package:solana/dto.dart' show LatestBlockhash;
import 'package:solana/encoder.dart' show Message, Signature, SignedTx;
import 'package:solana/solana.dart'
    show
        Ed25519HDKeyPair,
        Ed25519HDPublicKey,
        SystemInstruction,
        lamportsPerSol,
        signTransaction;
import 'package:web3dart/crypto.dart' show hexToBytes;

import 'hd_wallet_service.dart';
import 'mnemonic_service.dart';

/// 后端 `createTransaction` 返回未签名交易或 **system.transfer** 字段，客户端签名后
/// `broadcastTransaction`（`data` 为 base64 已签交易）。
abstract final class SolanaBackendTransfer {
  SolanaBackendTransfer._();

  static Future<Ed25519HDKeyPair> keyPairFromMnemonic(String mnemonic) async {
    final phrase = mnemonic.trim();
    final seedHex = MnemonicService.mnemonicToSeedHex(phrase);
    final normalizedHex =
        seedHex.startsWith('0x') || seedHex.startsWith('0X') ? seedHex : '0x$seedHex';
    final seed = hexToBytes(normalizedHex);
    return Ed25519HDKeyPair.fromSeedWithHdPath(
      seed: seed,
      hdPath: kSolanaDefaultDerivationPath,
    );
  }

  /// 从 `createTransaction` 的 `data` 中取出未签名交易（base64 或 `0x` hex）。
  static String? readUnsignedPayload(Map<String, dynamic> data) {
    String? fromValue(Object? v) {
      if (v is! String) return null;
      final s = v.trim();
      return s.isEmpty ? null : s;
    }

    for (final k in const [
      'serializedTransaction',
      'unsignedTransaction',
      'transaction',
      'txBase64',
      'tx',
      'data',
    ]) {
      final hit = fromValue(data[k]);
      if (hit != null) return hit;
    }
    final inner = data['transaction'];
    if (inner is Map) {
      final m = Map<String, dynamic>.from(inner);
      for (final k in const ['serializedTransaction', 'unsignedTransaction', 'transaction']) {
        final hit = fromValue(m[k]);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  static SignedTx _parseUnsignedTx(String payload) {
    final s = payload.trim();
    if (s.startsWith('0x') || s.startsWith('0X')) {
      return SignedTx.fromBytes(hexToBytes(s));
    }
    return SignedTx.decode(s);
  }

  static bool _isBlankSig(List<int> bytes) {
    if (bytes.length < 64) return true;
    return bytes.every((b) => b == 0);
  }

  /// 对 [unsignedPayload] 解码后，为所有必填签名位写入签名（本钱包位用 [signer]，其余位须已有有效签名）。
  static Future<String> signTransactionPayload({
    required String unsignedPayload,
    required Ed25519HDKeyPair signer,
  }) async {
    final tx = _parseUnsignedTx(unsignedPayload);
    final cm = tx.compiledMessage;
    final messageBytes = cm.toByteArray();
    final n = cm.requiredSignatureCount;
    final keys = cm.accountKeys;
    if (keys.length < n) {
      throw StateError('Solana 交易账户数不足');
    }
    final out = <Signature>[];
    for (var i = 0; i < n; i++) {
      final pk = keys[i];
      if (pk == signer.publicKey) {
        out.add(await signer.sign(messageBytes));
      } else {
        final prev = i < tx.signatures.length ? tx.signatures[i] : null;
        if (prev != null && !_isBlankSig(prev.bytes)) {
          out.add(prev);
        } else {
          throw StateError('Solana 交易缺少第 ${i + 1} 个签名（共需 $n 个）');
        }
      }
    }
    return SignedTx(compiledMessage: cm, signatures: out).encode();
  }

  static bool _isSystemTransferLayout(Map<String, dynamic> data) {
    final t = data['type']?.toString().trim().toLowerCase() ?? '';
    return t == 'system.transfer' || t == 'system_transfer';
  }

  static int _lamportsFromAmountSol(num amountSol) {
    final lam = (amountSol.toDouble() * lamportsPerSol).round();
    if (lam <= 0) {
      throw StateError('转账金额须大于 0');
    }
    return lam;
  }

  static int _readLastValidBlockHeight(Object? raw) {
    if (raw == null) return 0;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  /// 根据 `createTransaction` 的 `data` 完成签名：优先 **整包未签交易**；否则识别
  /// **`type: system.transfer` + `from`/`to`/`recentBlockhash`/`lastValidBlockHeight`**，
  /// 使用与请求一致的 [amountSol] 换算 lamports 组装系统转账并签名。
  ///
  /// [expectedOwnerBase58] 须与 `from` 及本钱包派生地址一致。
  static Future<String> signCreateTransactionData({
    required Map<String, dynamic> data,
    required Ed25519HDKeyPair signer,
    required String expectedOwnerBase58,
    required num amountSol,
  }) async {
    final embedded = readUnsignedPayload(data);
    if (embedded != null) {
      return signTransactionPayload(
        unsignedPayload: embedded,
        signer: signer,
      );
    }
    if (!_isSystemTransferLayout(data)) {
      throw StateError(
        'createTransaction 返回格式不支持（需 serializedTransaction 或 type=system.transfer）',
      );
    }
    final from = data['from']?.toString().trim() ?? '';
    final to = data['to']?.toString().trim() ?? '';
    final recentBlockhash = data['recentBlockhash']?.toString().trim() ?? '';
    if (from.isEmpty || to.isEmpty || recentBlockhash.isEmpty) {
      throw StateError('system.transfer 缺少 from / to / recentBlockhash');
    }
    final funding = Ed25519HDPublicKey.fromBase58(from);
    if (funding != signer.publicKey) {
      throw StateError('返回的 from 与当前钱包地址不一致');
    }
    if (from != expectedOwnerBase58.trim()) {
      throw StateError('返回的 from 与付款地址不一致');
    }
    final recipient = Ed25519HDPublicKey.fromBase58(to);
    final lamports = _lamportsFromAmountSol(amountSol);
    final ix = SystemInstruction.transfer(
      fundingAccount: funding,
      recipientAccount: recipient,
      lamports: lamports,
    );
    final message = Message.only(ix);
    final lvb = _readLastValidBlockHeight(data['lastValidBlockHeight']);
    final latest = LatestBlockhash(
      blockhash: recentBlockhash,
      lastValidBlockHeight: lvb,
    );
    final signed = await signTransaction(latest, message, [signer]);
    return signed.encode();
  }
}

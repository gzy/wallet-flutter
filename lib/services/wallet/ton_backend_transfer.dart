import 'package:ton_dart/ton_dart.dart';

import 'hd_wallet_service.dart';
import 'ton_rpc_http_provider.dart';

/// TON：`createTransaction` 若已含可广播 BOC 则透传；`signing: client` / `ton.transfer` 时本地 WalletV4 签名。
abstract final class TonBackendTransfer {
  TonBackendTransfer._();

  static const _tonApiMainnet = 'https://tonapi.io';
  static const _tonApiTestnet = 'https://testnet.tonapi.io';
  static const _tonCenterMainnet =
      'https://toncenter.com/api/v2/jsonRPC';
  static const _tonCenterTestnet =
      'https://testnet.toncenter.com/api/v2/jsonRPC';

  static Future<TonPrivateKey> privateKeyFromMnemonic(String mnemonic) =>
      HdWalletService.tonPrivateKeyFromMnemonic(mnemonic);

  static TonProvider rpcForNetwork({required bool testOnly}) {
    return TonProvider(
      TonRpcHttpProvider(
        tonApiUrl: testOnly ? _tonApiTestnet : _tonApiMainnet,
        tonCenterUrl: testOnly ? _tonCenterTestnet : _tonCenterMainnet,
        api: TonApiType.tonApi,
      ),
    );
  }

  /// 优先返回已签好、可直接作为 `broadcastTransaction.data` 的字符串（常见字段名兼容）。
  static String? readPreSignedBroadcastPayload(Map<String, dynamic> data) {
    String? pick(Object? v) {
      if (v is! String) return null;
      final s = v.trim();
      return s.isEmpty ? null : s;
    }

    for (final k in const [
      'signedBoc',
      'signedMessage',
      'serializedMessage',
      'boc',
      'transaction',
      'payload',
    ]) {
      final hit = pick(data[k]);
      if (hit != null) return hit;
    }
    final signing = data['signing']?.toString().trim().toLowerCase();
    if (signing == 'client') {
      return null;
    }
    final embedded = pick(data['data']);
    if (embedded != null) return embedded;
    return null;
  }

  static bool _isTonTransferLayout(Map<String, dynamic> data) {
    final t = data['type']?.toString().trim().toLowerCase() ?? '';
    return t == 'ton.transfer' || t == 'ton_transfer';
  }

  static bool _networkIsTestnet(Map<String, dynamic> data) {
    final n = data['network']?.toString().trim().toLowerCase() ?? '';
    return n == 'testnet' || n.contains('test');
  }

  static BigInt _amountNanoFromData(
    Map<String, dynamic> data, {
    required num? fallbackAmountTon,
  }) {
    final raw = data['amountNano'] ?? data['amount_nano'];
    if (raw != null) {
      if (raw is BigInt) return raw;
      if (raw is int) return BigInt.from(raw);
      final parsed = BigInt.tryParse(raw.toString().trim());
      if (parsed != null && parsed > BigInt.zero) return parsed;
    }
    final amount = data['amount'];
    if (amount is num && amount > 0) {
      return TonHelper.toNano(amount.toString());
    }
    if (fallbackAmountTon != null && fallbackAmountTon > 0) {
      return TonHelper.toNano(fallbackAmountTon.toString());
    }
    throw StateError('TON 转账金额无效');
  }

  static String _friendly(TonAddress addr, {required bool testOnly}) {
    return addr.toFriendlyAddress(
      bounceable: false,
      testOnly: testOnly,
      urlSafe: true,
    );
  }

  static bool _sameFriendlyAddress(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x == y) return true;
    try {
      return TonAddress(x).toRawAddress() == TonAddress(y).toRawAddress();
    } catch (_) {
      return false;
    }
  }

  /// 根据 `createTransaction` 的 `data` 完成 WalletV4 签名，返回 base64 BOC。
  static Future<String> signCreateTransactionData({
    required Map<String, dynamic> data,
    required TonPrivateKey privateKey,
    required String expectedOwnerFriendly,
    required bool testOnly,
    num? fallbackAmountTon,
  }) async {
    final pre = readPreSignedBroadcastPayload(data);
    if (pre != null) return pre;

    if (!_isTonTransferLayout(data)) {
      final signing = data['signing']?.toString().trim().toLowerCase();
      if (signing != 'client') {
        throw StateError(
          'createTransaction 返回格式不支持（需已签 BOC 或 type=ton.transfer）',
        );
      }
    }

    final from = data['from']?.toString().trim() ?? '';
    final to = data['to']?.toString().trim() ?? '';
    if (from.isEmpty || to.isEmpty) {
      throw StateError('ton.transfer 缺少 from / to');
    }
    if (!_sameFriendlyAddress(from, expectedOwnerFriendly.trim())) {
      throw StateError('返回的 from 与当前钱包地址不一致');
    }

    final netTest = testOnly || _networkIsTestnet(data);
    final chain = netTest ? TonChainId.testnet : TonChainId.mainnet;
    final publicKey = privateKey.toPublicKey().toBytes();
    final wallet = WalletV4.create(
      chain: chain,
      publicKey: publicKey,
      bounceableAddress: false,
    );
    final ownerFriendly = _friendly(wallet.address, testOnly: netTest);
    if (!_sameFriendlyAddress(ownerFriendly, from)) {
      throw StateError('本地派生地址与 createTransaction.from 不一致');
    }

    final amountNano = _amountNanoFromData(
      data,
      fallbackAmountTon: fallbackAmountTon,
    );
    final dest = TonAddress(to);
    final rpc = rpcForNetwork(testOnly: netTest);

    return wallet.sendTransfer(
      params: VersionedTransferParams(
        privateKey: privateKey,
        messages: [
          OutActionSendMsg(
            outMessage: TonHelper.internal(
              destination: dest,
              amount: amountNano,
            ),
          ),
        ],
      ),
      rpc: rpc,
      onEstimateFee: null,
      action: TonTransactionAction.boc,
    );
  }

  /// 若 [data] 中已有可广播载荷则返回；否则本地签名后返回 base64 BOC。
  static Future<String> prepareBroadcastData({
    required Map<String, dynamic> data,
    required TonPrivateKey privateKey,
    required String expectedOwnerFriendly,
    required bool testOnly,
    num? fallbackAmountTon,
  }) {
    return signCreateTransactionData(
      data: data,
      privateKey: privateKey,
      expectedOwnerFriendly: expectedOwnerFriendly,
      testOnly: testOnly,
      fallbackAmountTon: fallbackAmountTon,
    );
  }
}

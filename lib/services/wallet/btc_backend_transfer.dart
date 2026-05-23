import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';

/// 钱包聚合 `POST /api/app/wallet/createTransaction`（BTC）的本地签名。
///
/// OpenAPI 通常不把 `data` 细化到 BTC；当前实现按常见网关约定支持：
/// - **PSBT**：`data` 为 Base64 或 hex 字符串，或 Map 内 `psbt` / `psbtBase64` / `unsignedPsbt` 等键。
/// - **Uone 风格**：`txHex` 为未签名裸交易 + `txInput[]` 每项含上一笔完整 `txHex`（non-witness UTXO），
///   组装 PSBT 后本地签名再输出 raw hex。
/// - **已签名 raw**：`hex` / `rawTx` / `transactionHex` 等为**链上可验证已签名**的完整交易 hex。
///
/// 签名流程：PSBT → [PsbtBuilder.signAllInput] → [PsbtBuilder.finalizeAll] → raw hex。
class BtcBackendTransfer {
  BtcBackendTransfer._();

  static const _psbtMapKeys = <String>[
    'psbt',
    'psbtBase64',
    'unsignedPsbt',
    'unsignedTransaction',
    'base64',
  ];

  /// 可能被误当成「裸 hex」的键；仅当反序列化后**确有签名**才直通广播。
  static const _signedRawHexKeys = <String>[
    'hex',
    'transactionHex',
    'rawTx',
  ];

  /// 从 `createTransaction` 的 `data` 解析载荷并签名，返回 `broadcastTransaction` 用的 **raw tx hex**（无 `0x` 前缀）。
  static String signCreateTransactionData({
    required Map<String, dynamic> data,
    required ECPrivate ownerPrivateKey,
    required String expectedOwnerAddress,
    required bool testnet,
    bool doge = false,
  }) {
    final psbtLike = _extractPsbtString(data);
    if (psbtLike != null && psbtLike.isNotEmpty) {
      return _signPsbtToRawHex(
        psbtLike,
        ownerPrivateKey,
        expectedOwnerAddress,
        testnet: testnet,
        doge: doge,
      );
    }
    final txHex = data['txHex']?.toString().trim();
    final txInputRaw = data['txInput'];
    if (txHex != null &&
        txHex.isNotEmpty &&
        txInputRaw is List &&
        txInputRaw.isNotEmpty) {
      return _signWalletTxHexWithPrevTxs(
        txHex: txHex,
        txInputList: txInputRaw,
        ownerPrivateKey: ownerPrivateKey,
        expectedOwnerAddress: expectedOwnerAddress,
        testnet: testnet,
        doge: doge,
      );
    }
    for (final k in _signedRawHexKeys) {
      final v = data[k];
      if (v is String && _looksLikeSignedRawTx(v.trim())) {
        return _normalizeHex(v.trim());
      }
    }
    throw StateError(
      'BTC createTransaction.data 缺少可识别的 PSBT、txHex+txInput 组合，或已签名 raw（'
      'PSBT 键: ${_psbtMapKeys.join(", ")}；已签裸交易键: ${_signedRawHexKeys.join(", ")}）',
    );
  }

  static String? _extractPsbtString(Map<String, dynamic> data) {
    for (final k in _psbtMapKeys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) {
        return v.trim();
      }
    }
    for (final k in _signedRawHexKeys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) {
        final t = v.trim();
        if (_looksLikePsbtHex(t)) {
          return t;
        }
      }
    }
    final txHex = data['txHex']?.toString().trim();
    if (txHex != null && txHex.isNotEmpty && _looksLikePsbtHex(txHex)) {
      return txHex;
    }
    return null;
  }

  static bool _looksLikePsbtHex(String s) {
    final x = s.startsWith('0x') || s.startsWith('0X') ? s.substring(2) : s;
    if (x.length < 20) return false;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(x)) return false;
    try {
      final bytes = BytesUtils.fromHexString(x);
      return bytes.length >= 5 &&
          bytes[0] == 0x70 &&
          bytes[1] == 0x73 &&
          bytes[2] == 0x62 &&
          bytes[3] == 0x74;
    } catch (_) {
      return false;
    }
  }

  /// 仅当可反序列化为交易且 witness/scriptSig 表明已签名时，才视为可直传的已签 raw。
  static bool _looksLikeSignedRawTx(String s) {
    try {
      final tx = BtcTransaction.deserialize(
        BytesUtils.fromHexString(_normalizeHex(s)),
        allowWitness: true,
      );
      return _appearsFullySignedOnWire(tx);
    } catch (_) {
      return false;
    }
  }

  /// 裸 segwit 未签交易在链上序列化里常无 witness；已签则 witness 栈非空或 legacy scriptSig 非空。
  static bool _appearsFullySignedOnWire(BtcTransaction tx) {
    if (tx.witnesses.isNotEmpty) {
      for (final w in tx.witnesses) {
        for (final item in w.stack) {
          final b = BytesUtils.tryFromHexString(item);
          if (b != null && b.length >= 64) {
            return true;
          }
        }
      }
    }
    return tx.inputs.any((i) => i.scriptSig.script.isNotEmpty);
  }

  static String _normalizeHex(String s) {
    final t = s.trim();
    if (t.startsWith('0x') || t.startsWith('0X')) {
      return t.substring(2).toLowerCase();
    }
    return t.toLowerCase();
  }

  static void _assertOwnerMatches(
    ECPrivate ownerPrivateKey,
    String expectedOwnerAddress, {
    required bool testnet,
    required bool doge,
  }) {
    final want = expectedOwnerAddress.trim();
    if (doge) {
      final network =
          testnet ? DogecoinNetwork.testnet : DogecoinNetwork.mainnet;
      final p2pkh = ownerPrivateKey.getPublic().toAddress();
      final derived =
          DogeAddress.fromBaseAddress(p2pkh, network: network).address.trim();
      if (derived != want) {
        throw StateError('DOGE 派生地址与当前 owner 不一致');
      }
      return;
    }
    final network =
        testnet ? BitcoinNetwork.testnet : BitcoinNetwork.mainnet;
    final derived = ownerPrivateKey
        .getPublic()
        .toSegwitAddress()
        .toAddress(network)
        .trim()
        .toLowerCase();
    if (derived != want.toLowerCase()) {
      throw StateError('BTC 派生地址与当前 owner 不一致');
    }
  }

  static BitcoinAddressType _bitcoinAddressTypeForScriptPubKey(
    Script scriptPubKey,
  ) {
    final t = BitcoinScriptUtils.findScriptType(scriptPubKey);
    if (t == null) {
      throw StateError('BTC: 无法识别 UTXO scriptPubKey 类型');
    }
    return switch (t) {
      ScriptPubKeyType.p2pkh => P2pkhAddressType.p2pkh,
      ScriptPubKeyType.p2wpkh => SegwitAddressType.p2wpkh,
      ScriptPubKeyType.p2wsh => SegwitAddressType.p2wsh,
      ScriptPubKeyType.p2tr => SegwitAddressType.p2tr,
      ScriptPubKeyType.p2pk => PubKeyAddressType.p2pk,
      ScriptPubKeyType.p2sh ||
      ScriptPubKeyType.p2sh32 =>
        throw StateError('BTC: 当前不支持从 P2SH 载荷自动推断 redeemScript，请改用 PSBT'),
    };
  }

  /// 后端返回 `txHex`（未签）+ `txInput`（每项含上一笔完整交易 `txHex`）时的签名路径。
  static String _signWalletTxHexWithPrevTxs({
    required String txHex,
    required List<dynamic> txInputList,
    required ECPrivate ownerPrivateKey,
    required String expectedOwnerAddress,
    required bool testnet,
    bool doge = false,
  }) {
    _assertOwnerMatches(
      ownerPrivateKey,
      expectedOwnerAddress,
      testnet: testnet,
      doge: doge,
    );
    final unsignedSpend = BtcTransaction.deserialize(
      BytesUtils.fromHexString(_normalizeHex(txHex)),
      allowWitness: true,
    );
    if (_appearsFullySignedOnWire(unsignedSpend)) {
      return unsignedSpend.serialize();
    }
    if (unsignedSpend.inputs.length != txInputList.length) {
      throw StateError(
        'BTC createTransaction: txInput 条数(${txInputList.length})与 '
        '未签名交易 inputs(${unsignedSpend.inputs.length})不一致',
      );
    }
    final inputEntries = <List<PsbtInputData>>[];
    for (var i = 0; i < unsignedSpend.inputs.length; i++) {
      final row = txInputList[i];
      if (row is! Map) {
        throw StateError('BTC createTransaction: txInput[$i] 应为对象');
      }
      final m = Map<String, dynamic>.from(row);
      final prevHex = (m['txHex'] ??
              m['prevTxHex'] ??
              m['transactionHex'] ??
              m['hex'])
          ?.toString()
          .trim();
      if (prevHex == null || prevHex.isEmpty) {
        throw StateError('BTC createTransaction: txInput[$i] 缺少 prev tx hex');
      }
      final prevTx = BtcTransaction.deserialize(
        BytesUtils.fromHexString(_normalizeHex(prevHex)),
        allowWitness: true,
      );
      final inp = unsignedSpend.inputs[i];
      final vout = inp.txIndex;
      final idxRaw = m['index'] ?? m['vout'] ?? m['outputIndex'];
      if (idxRaw != null) {
        final j = int.tryParse(idxRaw.toString());
        if (j != null && j != vout) {
          throw StateError(
            'BTC createTransaction: txInput[$i].index($j) 与未签 input 的 vout($vout)不一致',
          );
        }
      }
      if (prevTx.txId() != inp.txId) {
        throw StateError(
          'BTC createTransaction: txInput[$i] 的 prev tx 与 spending input 不匹配',
        );
      }
      if (vout < 0 || vout >= prevTx.outputs.length) {
        throw StateError('BTC createTransaction: txInput[$i] vout 越界');
      }
      final out = prevTx.outputs[vout];
      _bitcoinAddressTypeForScriptPubKey(out.scriptPubKey);
      final psbtIn = PsbtTransactionInput.witnessV0(
        outIndex: vout,
        txId: inp.txId,
        nonWitnessUtxo: prevTx,
        scriptPubKey: out.scriptPubKey,
      );
      inputEntries.add(psbtIn.toPsbtInputs(PsbtVersion.v0));
    }
    final psbt = Psbt(
      global: PsbtGlobal(
        version: PsbtVersion.v0,
        entries: [
          PsbtGlobalPSBTVersionNumber(PsbtVersion.v0),
          PsbtGlobalUnsignedTransaction(unsignedSpend),
        ],
      ),
      input: PsbtInput(version: PsbtVersion.v0, entries: inputEntries),
      output: PsbtOutput(
        version: PsbtVersion.v0,
        entries: List.generate(unsignedSpend.outputs.length, (_) => []),
      ),
    );
    final builder = PsbtBuilder.fromPsbt(psbt);
    builder.signAllInput((params) {
      return PsbtSignerResponse(
        signers: [PsbtDefaultSigner(ownerPrivateKey)],
      );
    });
    final tx = builder.finalizeAll();
    return tx.serialize();
  }

  static String _signPsbtToRawHex(
    String psbtInput,
    ECPrivate ownerPrivateKey,
    String expectedOwnerAddress, {
    required bool testnet,
    required bool doge,
  }) {
    _assertOwnerMatches(
      ownerPrivateKey,
      expectedOwnerAddress,
      testnet: testnet,
      doge: doge,
    );

    final PsbtBuilder builder = _psbtBuilderFromString(psbtInput);
    builder.signAllInput((params) {
      return PsbtSignerResponse(
        signers: [PsbtDefaultSigner(ownerPrivateKey)],
      );
    });
    final tx = builder.finalizeAll();
    return tx.serialize();
  }

  static PsbtBuilder _psbtBuilderFromString(String raw) {
    final t = raw.trim();
    try {
      return PsbtBuilder.fromBase64(t);
    } catch (_) {}
    try {
      final hex = t.startsWith('0x') || t.startsWith('0X') ? t.substring(2) : t;
      return PsbtBuilder.fromHex(hex);
    } catch (_) {}
    throw StateError('无法将 BTC createTransaction 载荷解析为 PSBT');
  }
}

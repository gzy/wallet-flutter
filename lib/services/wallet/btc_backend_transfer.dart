import 'dart:convert';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart';

/// 钱包聚合 `POST /api/app/wallet/createTransaction`（BTC / DOGE）的本地签名。
///
/// OpenAPI 通常不把 `data` 细化到 UTXO 链；当前实现按常见网关约定支持：
/// - **PSBT**：Map 内 `psbt` / `psbtBase64` / `unsignedPsbt` 等，或 `data` 本身为 PSBT 字符串。
/// - **Uone 风格**：`txHex` 为未签名裸交易 + `txInput[]` 每项含上一笔完整 `txHex`（non-witness UTXO）。
/// - **已签名 raw**：`hex` / `rawTx` / `transactionHex` 等为**链上可验证已签名**的完整交易 hex。
class BtcBackendTransfer {
  BtcBackendTransfer._();

  static const _psbtMapKeys = <String>[
    'psbt',
    'psbtBase64',
    'psbtHex',
    'unsignedPsbt',
    'unsignedTransaction',
    'unsignedPsbtHex',
    'base64',
  ];

  static const _signedRawHexKeys = <String>[
    'hex',
    'transactionHex',
    'rawTx',
    'signedTxHex',
    'signedTransactionHex',
  ];

  static const _txHexKeys = <String>[
    'txHex',
    'tx_hex',
    'unsignedTxHex',
    'unsignedTransactionHex',
    'unsigned_tx_hex',
    'rawTransaction',
    'transactionHex',
  ];

  static const _txInputKeys = <String>[
    'txInput',
    'txInputs',
    'tx_input',
    'tx_inputs',
    'inputs',
    'utxos',
  ];

  static const _nestedPayloadKeys = <String>[
    'transaction',
    'tx',
    'unsignedTransaction',
    'unsignedTx',
    'result',
    'body',
    'data',
  ];

  static const _feeKeys = <String>[
    'fee',
    'transactionFee',
    'networkFee',
    'minerFee',
    'gasFee',
    'estimatedFee',
  ];

  static const _totalInputKeys = <String>[
    'totalInput',
    'totalInputValue',
    'inputValue',
    'inputAmount',
  ];

  /// 将 `createTransaction.data`（Map / String / 嵌套结构）规范化为签名器可识别的 Map。
  static Map<String, dynamic> normalizeCreateTransactionPayload(Object? raw) {
    if (raw == null) {
      return {};
    }
    if (raw is String) {
      return _normalizeStringPayload(raw.trim());
    }
    if (raw is Map) {
      return _flattenUtxoPayload(Map<String, dynamic>.from(raw));
    }
    throw FormatException(
      'createTransaction.data 应为 Map 或字符串，实际为 ${raw.runtimeType}',
    );
  }

  static Map<String, dynamic> _normalizeStringPayload(String s) {
    if (s.isEmpty) {
      return {};
    }
    if (_looksLikePsbtBase64(s)) {
      return {'psbtBase64': s};
    }
    if (_looksLikePsbtHex(s)) {
      return {'psbt': s};
    }
    if (_looksLikeSignedRawTx(s)) {
      return {'hex': s};
    }
    return {'txHex': s};
  }

  static Map<String, dynamic> _flattenUtxoPayload(Map<String, dynamic> source) {
    var out = Map<String, dynamic>.from(source);

    if (!_hasRecognizedUtxoFields(out)) {
      for (final key in _nestedPayloadKeys) {
        final inner = out[key];
        if (inner is Map) {
          final nested = Map<String, dynamic>.from(inner);
          if (_hasDecodedVinVout(nested)) {
            final merged = {...out, ...nested}..remove(key);
            out = merged;
            break;
          }
          final flatNested = _flattenUtxoPayload(nested);
          if (_hasRecognizedUtxoFields(flatNested)) {
            out = {...out, ...flatNested}..remove(key);
            break;
          }
        } else if (inner is String && inner.trim().isNotEmpty) {
          final nested = _normalizeStringPayload(inner.trim());
          if (_hasRecognizedUtxoFields(nested)) {
            out = {...out, ...nested}..remove(key);
            break;
          }
        }
      }
    }

    for (final key in _txHexKeys) {
      _aliasKey(out, key, 'txHex');
    }
    for (final key in _txInputKeys) {
      _aliasKey(out, key, 'txInput');
    }
    for (final key in _psbtMapKeys) {
      if (out.containsKey(key) && out[key] is String) {
        final v = out[key]!.toString().trim();
        if (v.isNotEmpty) {
          out[key] = v;
        }
      }
    }

    final txInput = out['txInput'];
    if (txInput is List) {
      out['txInput'] = txInput.map(_normalizeTxInputRow).toList();
    }

    return out;
  }

  static dynamic _normalizeTxInputRow(dynamic row) {
    if (row is! Map) {
      return row;
    }
    final m = Map<String, dynamic>.from(row);
    for (final key in const [
      'prevTxHex',
      'prev_tx_hex',
      'prevTx',
      'prevRawTx',
      'rawTx',
      'raw',
      'transactionHex',
      'utxoTxHex',
      'utxo_tx_hex',
    ]) {
      _aliasKey(m, key, 'txHex');
    }
    for (final key in const ['vout', 'outputIndex', 'output_index']) {
      _aliasKey(m, key, 'index');
    }
    return m;
  }

  static void _aliasKey(
    Map<String, dynamic> map,
    String from,
    String to,
  ) {
    if (map.containsKey(to)) {
      return;
    }
    final v = map[from];
    if (v == null) {
      return;
    }
    if (v is String && v.trim().isEmpty) {
      return;
    }
    map[to] = v;
  }

  static bool _hasDecodedVinVout(Map<String, dynamic> data) {
    final vin = data['vin'];
    final vout = data['vout'];
    return vin is List && vin.isNotEmpty && vout is List && vout.isNotEmpty;
  }

  static bool _hasRecognizedUtxoFields(Map<String, dynamic> data) {
    if (_extractPsbtString(data) != null) {
      return true;
    }
    if (_hasDecodedVinVout(data)) {
      return true;
    }
    final txHex = data['txHex']?.toString().trim();
    final txInput = data['txInput'];
    if (txHex != null &&
        txHex.isNotEmpty &&
        txInput is List &&
        txInput.isNotEmpty) {
      return true;
    }
    for (final k in _signedRawHexKeys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// 从 `broadcastTransaction.data`（含 JSON-RPC `result.txid` 嵌套）解析 txid。
  static String? parseBroadcastTxHash(Object? data) {
    if (data == null) {
      return null;
    }
    if (data is String) {
      final t = data.trim();
      return t.isEmpty ? null : t;
    }
    if (data is! Map) {
      return null;
    }
    final m = Map<String, dynamic>.from(data);
    const keys = <String>['txHash', 'hash', 'transactionHash', 'txid'];
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) {
        return v.trim();
      }
    }
    final result = m['result'];
    if (result is Map) {
      return parseBroadcastTxHash(result);
    }
    return null;
  }

  /// decoderawtransaction 载荷里的虚拟体积（vB），用于 `txSize × 费率` 推算手续费。
  static int? parseTxVsizeFromDecoded(Map<String, dynamic> data) {
    for (final k in const [
      'vsize',
      'virtualSize',
      'virtual_size',
      'txSize',
      'tx_size',
      'size',
    ]) {
      final v = data[k];
      if (v is int && v > 0) {
        return v;
      }
      if (v is num) {
        final i = v.round();
        if (i > 0) {
          return i;
        }
      }
      if (v is String) {
        final p = int.tryParse(v.trim());
        if (p != null && p > 0) {
          return p;
        }
      }
    }
    return null;
  }

  static String _chainLabel({required bool doge}) => doge ? 'DOGE' : 'BTC';

  /// 从 `createTransaction` 的 `data` 解析载荷并签名，返回 `broadcastTransaction` 用的 **raw tx hex**（无 `0x` 前缀）。
  static String signCreateTransactionData({
    required Map<String, dynamic> data,
    required ECPrivate ownerPrivateKey,
    required String expectedOwnerAddress,
    required bool testnet,
    bool doge = false,
  }) {
    final normalized = _flattenUtxoPayload(Map<String, dynamic>.from(data));
    final label = _chainLabel(doge: doge);

    final psbtLike = _extractPsbtString(normalized);
    if (psbtLike != null && psbtLike.isNotEmpty) {
      return _signPsbtToRawHex(
        psbtLike,
        ownerPrivateKey,
        expectedOwnerAddress,
        testnet: testnet,
        doge: doge,
      );
    }
    final txHex = normalized['txHex']?.toString().trim();
    final txInputRaw = normalized['txInput'];
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
      final v = normalized[k];
      if (v is String && _looksLikeSignedRawTx(v.trim())) {
        return _normalizeHex(v.trim());
      }
    }
    if (_hasDecodedVinVout(normalized)) {
      return _signDecodedVinVoutTransaction(
        decoded: normalized,
        ownerPrivateKey: ownerPrivateKey,
        expectedOwnerAddress: expectedOwnerAddress,
        testnet: testnet,
        doge: doge,
      );
    }
    if (kDebugMode) {
      debugPrint(
        '$label createTransaction.data 未识别，顶层键: ${normalized.keys.join(", ")}',
      );
    }
    throw StateError(
      '$label createTransaction.data 缺少可识别的 PSBT、txHex+txInput 组合，或已签名 raw（'
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

  static bool _looksLikePsbtBase64(String s) {
    final t = s.trim();
    if (t.startsWith('cHNi') || t.startsWith('cHNidP')) {
      return true;
    }
    try {
      final bytes = base64.decode(t);
      return bytes.length >= 5 &&
          bytes[0] == 0x70 &&
          bytes[1] == 0x73 &&
          bytes[2] == 0x62 &&
          bytes[3] == 0x74;
    } catch (_) {
      return false;
    }
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

  static PsbtTransactionInput _psbtInputForOutput({
    required TxInput inp,
    required int vout,
    required BtcTransaction prevTx,
    required Script scriptPubKey,
    required bool doge,
  }) {
    final scriptType = BitcoinScriptUtils.findScriptType(scriptPubKey);
    if (scriptType == null) {
      throw StateError('UTXO: 无法识别 scriptPubKey 类型');
    }
    if (doge || scriptType == ScriptPubKeyType.p2pkh) {
      return PsbtTransactionInput.legacy(
        outIndex: vout,
        txId: inp.txId,
        nonWitnessUtxo: prevTx,
        scriptPubKey: scriptPubKey,
      );
    }
    if (scriptType == ScriptPubKeyType.p2wpkh) {
      return PsbtTransactionInput.witnessV0(
        outIndex: vout,
        txId: inp.txId,
        nonWitnessUtxo: prevTx,
        scriptPubKey: scriptPubKey,
      );
    }
    if (scriptType == ScriptPubKeyType.p2wsh) {
      return PsbtTransactionInput.witnessV0(
        outIndex: vout,
        txId: inp.txId,
        nonWitnessUtxo: prevTx,
        scriptPubKey: scriptPubKey,
      );
    }
    throw StateError('UTXO: 当前不支持 script 类型 ${scriptType.name}');
  }

  static String _signWalletTxHexWithPrevTxs({
    required String txHex,
    required List<dynamic> txInputList,
    required ECPrivate ownerPrivateKey,
    required String expectedOwnerAddress,
    required bool testnet,
    bool doge = false,
  }) {
    final label = _chainLabel(doge: doge);
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
        '$label createTransaction: txInput 条数(${txInputList.length})与 '
        '未签名交易 inputs(${unsignedSpend.inputs.length})不一致',
      );
    }
    final inputEntries = <List<PsbtInputData>>[];
    for (var i = 0; i < unsignedSpend.inputs.length; i++) {
      final row = txInputList[i];
      if (row is! Map) {
        throw StateError('$label createTransaction: txInput[$i] 应为对象');
      }
      final m = Map<String, dynamic>.from(row);
      final prevHex = (m['txHex'] ??
              m['prevTxHex'] ??
              m['transactionHex'] ??
              m['hex'])
          ?.toString()
          .trim();
      if (prevHex == null || prevHex.isEmpty) {
        throw StateError('$label createTransaction: txInput[$i] 缺少 prev tx hex');
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
            '$label createTransaction: txInput[$i].index($j) 与未签 input 的 vout($vout)不一致',
          );
        }
      }
      if (prevTx.txId() != inp.txId) {
        throw StateError(
          '$label createTransaction: txInput[$i] 的 prev tx 与 spending input 不匹配',
        );
      }
      if (vout < 0 || vout >= prevTx.outputs.length) {
        throw StateError('$label createTransaction: txInput[$i] vout 越界');
      }
      final out = prevTx.outputs[vout];
      final psbtIn = _psbtInputForOutput(
        inp: inp,
        vout: vout,
        prevTx: prevTx,
        scriptPubKey: out.scriptPubKey,
        doge: doge,
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
    throw StateError('无法将 createTransaction 载荷解析为 PSBT');
  }

  static List<int> _u32Le(int value) =>
      IntUtils.toBytes(value, length: 4, byteOrder: Endian.little);

  static List<int> _sequenceFromJson(dynamic raw) {
    final n = switch (raw) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v.trim()) ?? 0xffffffff,
      _ => 0xffffffff,
    };
    return _u32Le(n);
  }

  static BigInt _coinAmountToSat(dynamic raw) {
    if (raw == null) {
      throw FormatException('缺少金额');
    }
    final d = switch (raw) {
      num v => v.toDouble(),
      String v => double.parse(v.trim()),
      _ => throw FormatException('无法解析金额: $raw'),
    };
    return BigInt.from((d * 1e8).round());
  }

  /// decoderawtransaction 的 `scriptPubKey.hex` 已是完整锁定脚本字节，须 [Script.deserialize]。
  /// `Script(script: [hex])` 会把整段 hex 当作 push 数据再包一层长度前缀（多 `0x19`），
  /// 导致输出变 nonstandard、地址解析失败。
  static Script _scriptPubKeyFromVoutRow(Map<String, dynamic> row) {
    final spk = row['scriptPubKey'];
    if (spk is Map) {
      final hex = spk['hex']?.toString().trim();
      if (hex != null && hex.isNotEmpty) {
        return Script.deserialize(
          bytes: BytesUtils.fromHexString(_normalizeHex(hex)),
        );
      }
    }
    throw StateError('vout 缺少 scriptPubKey.hex');
  }

  @visibleForTesting
  static Script scriptPubKeyFromVoutRowForTest(Map<String, dynamic> row) =>
      _scriptPubKeyFromVoutRow(row);

  static BtcTransaction _btcTxFromDecodedVinVout(Map<String, dynamic> decoded) {
    final vin = decoded['vin'] as List;
    final vout = decoded['vout'] as List;
    final inputs = <TxInput>[];
    for (final row in vin) {
      if (row is! Map) {
        throw StateError('vin 条目应为对象');
      }
      final m = Map<String, dynamic>.from(row);
      final txid = (m['txid'] ?? m['hash'])?.toString().trim();
      if (txid == null || txid.isEmpty) {
        throw StateError('vin 缺少 txid');
      }
      final voutIndex = m['vout'] ?? m['outputIndex'] ?? m['index'];
      final idx = switch (voutIndex) {
        int v => v,
        num v => v.toInt(),
        String v => int.parse(v.trim()),
        _ => throw StateError('vin 缺少 vout'),
      };
      inputs.add(
        TxInput(
          txId: txid,
          txIndex: idx,
          sequance: _sequenceFromJson(m['sequence']),
        ),
      );
    }
    final outputs = <TxOutput>[];
    for (final row in vout) {
      if (row is! Map) {
        throw StateError('vout 条目应为对象');
      }
      final m = Map<String, dynamic>.from(row);
      outputs.add(
        TxOutput(
          amount: _coinAmountToSat(m['value']),
          scriptPubKey: _scriptPubKeyFromVoutRow(m),
        ),
      );
    }
    final locktime = decoded['locktime'];
    final version = decoded['version'];
    return BtcTransaction(
      inputs: inputs,
      outputs: outputs,
      locktime: locktime == null ? BitcoinOpCodeConst.defaultTxLocktime : _u32Le(
        switch (locktime) {
          int v => v,
          num v => v.toInt(),
          String v => int.parse(v.trim()),
          _ => 0,
        },
      ),
      version: version == null ? BitcoinOpCodeConst.defaultTxVersion : _u32Le(
        switch (version) {
          int v => v,
          num v => v.toInt(),
          String v => int.parse(v.trim()),
          _ => 1,
        },
      ),
    );
  }

  static BigInt? _parseOptionalFeeSat(Map<String, dynamic> data) {
    for (final k in _feeKeys) {
      final v = data[k];
      if (v == null) {
        continue;
      }
      try {
        return _coinAmountToSat(v);
      } catch (_) {}
    }
    return null;
  }

  static BigInt? _parseTotalInputSat(Map<String, dynamic> data) {
    for (final k in _totalInputKeys) {
      final v = data[k];
      if (v == null) {
        continue;
      }
      try {
        return _coinAmountToSat(v);
      } catch (_) {}
    }
    return null;
  }

  static BigInt _inputAmountSatForVin({
    required Map<String, dynamic> vinRow,
    required Map<String, dynamic> decoded,
    required List<dynamic> vout,
    required int vinCount,
    required int vinIndex,
  }) {
    final prevout = vinRow['prevout'];
    if (prevout is Map) {
      final value = prevout['value'];
      if (value != null) {
        return _coinAmountToSat(value);
      }
    }
    final direct = vinRow['value'] ?? vinRow['amount'];
    if (direct != null) {
      return _coinAmountToSat(direct);
    }
    for (final key in _txInputKeys) {
      final alt = decoded[key];
      if (alt is List && vinIndex < alt.length && alt[vinIndex] is Map) {
        final row = Map<String, dynamic>.from(alt[vinIndex] as Map);
        final amt = row['value'] ?? row['amount'] ?? row['satoshis'];
        if (amt != null) {
          return _coinAmountToSat(amt);
        }
      }
    }
    final totalInput = _parseTotalInputSat(decoded);
    if (totalInput != null) {
      return totalInput;
    }
    if (vinCount == 1) {
      var outSum = BigInt.zero;
      for (final row in vout) {
        if (row is Map) {
          outSum += _coinAmountToSat(row['value']);
        }
      }
      final fee = _parseOptionalFeeSat(decoded);
      if (fee != null) {
        return outSum + fee;
      }
    }
    throw StateError(
      'decoderawtransaction 格式缺少输入金额（vin.prevout.value、fee 或 totalInput）',
    );
  }

  static Script _ownerInputScriptPubKey({
    required ECPrivate ownerPrivateKey,
    required String expectedOwnerAddress,
    required bool testnet,
    required bool doge,
  }) {
    if (doge) {
      // bitcoin_base doge_example：P2PKH 用 legacy scriptCode，与派生地址一致。
      return ownerPrivateKey.getPublic().toAddress().toScriptPubKey();
    }
    return ownerPrivateKey
        .getPublic()
        .toSegwitAddress()
        .toScriptPubKey();
  }

  static String _signDecodedVinVoutTransaction({
    required Map<String, dynamic> decoded,
    required ECPrivate ownerPrivateKey,
    required String expectedOwnerAddress,
    required bool testnet,
    required bool doge,
  }) {
    final label = _chainLabel(doge: doge);
    _assertOwnerMatches(
      ownerPrivateKey,
      expectedOwnerAddress,
      testnet: testnet,
      doge: doge,
    );

    final txHex = decoded['txHex']?.toString().trim();
    final BtcTransaction unsignedSpend;
    if (txHex != null && txHex.isNotEmpty && !_looksLikePsbtHex(txHex)) {
      unsignedSpend = BtcTransaction.deserialize(
        BytesUtils.fromHexString(_normalizeHex(txHex)),
        allowWitness: true,
      );
    } else {
      unsignedSpend = _btcTxFromDecodedVinVout(decoded);
    }
    if (_appearsFullySignedOnWire(unsignedSpend)) {
      return unsignedSpend.serialize();
    }

    final vin = decoded['vin'] as List;
    final vout = decoded['vout'] as List;
    final ownerScript = _ownerInputScriptPubKey(
      ownerPrivateKey: ownerPrivateKey,
      expectedOwnerAddress: expectedOwnerAddress,
      testnet: testnet,
      doge: doge,
    );
    final pubHex =
        ownerPrivateKey.getPublic().toHex(mode: PublicKeyType.compressed);
    final witnesses = <TxWitnessInput>[];
    final isSegwitSpend = !doge &&
        BitcoinScriptUtils.findScriptType(ownerScript)?.isSegwit == true;

    for (var i = 0; i < unsignedSpend.inputs.length; i++) {
      if (doge) {
        // DOGE P2PKH：legacy digest + SIGHASH_ALL(0x01)，非 BCH/BSV 的 0x41。
        final digest = unsignedSpend.getTransactionDigest(
          txInIndex: i,
          script: ownerScript,
          sighash: BitcoinOpCodeConst.sighashAll,
        );
        final sigHex = ownerPrivateKey.signECDSA(
          digest,
          sighash: BitcoinOpCodeConst.sighashAll,
        );
        unsignedSpend.inputs[i].scriptSig =
            Script(script: [sigHex, pubHex]);
        continue;
      }

      final vinRow = vin[i] is Map
          ? Map<String, dynamic>.from(vin[i] as Map)
          : <String, dynamic>{};
      final inputAmount = _inputAmountSatForVin(
        vinRow: vinRow,
        decoded: decoded,
        vout: vout,
        vinCount: vin.length,
        vinIndex: i,
      );
      final sighash = BitcoinOpCodeConst.sighashAll;
      final digest = isSegwitSpend
          ? unsignedSpend.getTransactionSegwitDigit(
              txInIndex: i,
              script: ownerScript,
              amount: inputAmount,
              sighash: sighash,
            )
          : unsignedSpend.getTransactionDigest(
              txInIndex: i,
              script: ownerScript,
              sighash: sighash,
            );
      final sigHex = ownerPrivateKey.signECDSA(digest, sighash: sighash);
      if (isSegwitSpend) {
        unsignedSpend.inputs[i].scriptSig = Script(script: []);
        witnesses.add(TxWitnessInput(stack: [sigHex, pubHex]));
      } else {
        unsignedSpend.inputs[i].scriptSig =
            Script(script: [sigHex, pubHex]);
      }
    }

    var signed = unsignedSpend;
    if (isSegwitSpend) {
      signed = unsignedSpend.copyWith(witnesses: witnesses);
    }
    final wire = signed.serialize();
    if (kDebugMode) {
      debugPrint('$label 已签 decoderawtransaction 格式 (${wire.length ~/ 2} bytes)');
    }
    return wire;
  }

  /// decoderawtransaction 格式是否还缺输入金额/手续费提示。
  /// DOGE P2PKH 走 legacy sighash，不依赖输入金额。
  static bool needsInputFeeHint(
    Map<String, dynamic> normalized, {
    bool doge = false,
  }) {
    if (doge) {
      return false;
    }
    if (!_hasDecodedVinVout(normalized)) {
      return false;
    }
    if (_parseTotalInputSat(normalized) != null) {
      return false;
    }
    if (_parseOptionalFeeSat(normalized) != null) {
      return false;
    }
    final vin = normalized['vin'];
    if (vin is! List || vin.isEmpty) {
      return false;
    }
    for (final row in vin) {
      if (row is! Map) {
        continue;
      }
      final m = Map<String, dynamic>.from(row);
      final prevout = m['prevout'];
      if (prevout is Map && prevout['value'] != null) {
        return false;
      }
      if (m['value'] != null || m['amount'] != null) {
        return false;
      }
    }
    return vin.length == 1;
  }
}

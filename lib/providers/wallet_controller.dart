import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web3dart/web3dart.dart';

import '../models/coin_data.dart';
import '../models/evm_network.dart';
import '../models/stored_wallet.dart';
import '../services/evm/evm_client.dart';
import '../services/evm/send_service.dart';
import '../services/evm/token_service.dart';
import '../services/wallet/hd_wallet_service.dart';
import '../services/wallet/mnemonic_service.dart';
import '../services/wallet/secure_storage_service.dart';

/// 全局钱包状态：多钱包、PIN、助记词派生、EVM 余额、发送交易
class WalletController extends ChangeNotifier {
  WalletController({
    SecureStorageService? storage,
    TokenService? tokenService,
    SendService? sendService,
  })  : _storage = storage ?? SecureStorageService(),
        _tokenService = tokenService ?? TokenService(),
        _sendService = sendService ?? SendService();

  final SecureStorageService _storage;
  final TokenService _tokenService;
  final SendService _sendService;

  static const _uuid = Uuid();

  List<StoredWallet> _wallets = [];
  String? _activeWalletId;
  EthPrivateKey? _credentials;
  String? _addressHex;
  bool _backedUp = false;
  bool _loading = false;
  EvmNetworkId _sendNetwork = EvmNetworkId.ethereum;
  bool _pinEnabled = false;
  bool _sessionUnlocked = true;
  bool _initReady = false;

  List<CoinData> _evmCoins = [];

  bool get hasWallet => _credentials != null;
  String? get addressHex => _addressHex;
  EthereumAddress? get address =>
      _addressHex == null ? null : EthereumAddress.fromHex(_addressHex!);
  bool get backedUp => _backedUp;
  bool get loading => _loading;
  EvmNetworkId get sendNetwork => _sendNetwork;
  List<CoinData> get evmCoins => List.unmodifiable(_evmCoins);

  List<StoredWallet> get wallets => List.unmodifiable(_wallets);
  String? get activeWalletId => _activeWalletId;
  StoredWallet? get activeWallet {
    for (final w in _wallets) {
      if (w.id == _activeWalletId) {
        return w;
      }
    }
    return null;
  }

  bool get pinEnabled => _pinEnabled;
  bool get sessionUnlocked => _sessionUnlocked;
  bool get initReady => _initReady;

  void setSendNetwork(EvmNetworkId id) {
    _sendNetwork = id;
    notifyListeners();
  }

  Future<void> init() async {
    _initReady = false;
    notifyListeners();
    try {
      _pinEnabled = await _storage.hasPin();
      _wallets = await _storage.readWalletList();
      _activeWalletId = await _storage.getActiveWalletId();
      if (_activeWalletId == null && _wallets.isNotEmpty) {
        _activeWalletId = _wallets.first.id;
        await _storage.setActiveWalletId(_activeWalletId!);
      }
      if (_pinEnabled) {
        _sessionUnlocked = false;
      } else {
        _sessionUnlocked = true;
      }
      await _loadCredentialsFromActiveMnemonic();
    } catch (e, st) {
      debugPrint('WalletController.init failed: $e\n$st');
    } finally {
      _initReady = true;
      notifyListeners();
    }
    if (_credentials != null) {
      unawaited(refreshBalances());
    }
  }

  Future<void> _loadCredentialsFromActiveMnemonic() async {
    _credentials = null;
    _addressHex = null;
    _backedUp = false;
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    final m = await _storage.readMnemonicForWallet(id);
    if (m == null || m.isEmpty) {
      return;
    }
    try {
      _credentials = HdWalletService.privateKeyFromMnemonic(m);
      _addressHex = _credentials!.address.hex;
      final idx = _wallets.indexWhere((w) => w.id == id);
      _backedUp = idx >= 0
          ? _wallets[idx].backedUp
          : await _storage.readBackedUpForWallet(id);
    } catch (e, st) {
      debugPrint('Wallet init failed: $e\n$st');
      _credentials = null;
      _addressHex = null;
    }
  }

  /// 创建新钱包；若已设置 PIN 则校验 [pin]，否则写入 PIN。
  Future<void> createWallet(String pin) async {
    if (await _storage.hasPin()) {
      final r = await _storage.verifyPin(pin);
      if (!r.ok) {
        if (r.lockedSeconds != null && r.lockedSeconds! > 0) {
          throw StateError('PIN 已锁定，请 ${r.lockedSeconds}s 后再试');
        }
        throw StateError('PIN 不正确');
      }
    } else {
      await _storage.setPin(pin);
      _pinEnabled = true;
    }

    final m = MnemonicService.generateMnemonic();
    final id = _uuid.v4();
    final name = 'Wallet ${_wallets.length + 1}';

    await _storage.writeMnemonicForWallet(id, m);
    await _storage.writeBackedUpForWallet(id, false);
    final next = [
      ..._wallets,
      StoredWallet(id: id, name: name, backedUp: false)
    ];
    await _storage.writeWalletList(next);
    await _storage.setActiveWalletId(id);

    _wallets = next;
    _activeWalletId = id;
    _credentials = HdWalletService.privateKeyFromMnemonic(m);
    _addressHex = _credentials!.address.hex;
    _backedUp = false;
    _sessionUnlocked = true;
    await refreshBalances();
    notifyListeners();
  }

  /// 导入助记词钱包
  Future<void> importWallet(String mnemonic, String pin) async {
    final phrase = mnemonic.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (!MnemonicService.validateMnemonic(phrase)) {
      throw StateError('助记词无效');
    }
    if (await _storage.hasPin()) {
      final r = await _storage.verifyPin(pin);
      if (!r.ok) {
        if (r.lockedSeconds != null && r.lockedSeconds! > 0) {
          throw StateError('PIN 已锁定，请 ${r.lockedSeconds}s 后再试');
        }
        throw StateError('PIN 不正确');
      }
    } else {
      await _storage.setPin(pin);
      _pinEnabled = true;
    }

    final id = _uuid.v4();
    final name = 'Wallet ${_wallets.length + 1}';
    await _storage.writeMnemonicForWallet(id, phrase);
    await _storage.writeBackedUpForWallet(id, false);
    final next = [
      ..._wallets,
      StoredWallet(id: id, name: name, backedUp: false)
    ];
    await _storage.writeWalletList(next);
    await _storage.setActiveWalletId(id);

    _wallets = next;
    _activeWalletId = id;
    _credentials = HdWalletService.privateKeyFromMnemonic(phrase);
    _addressHex = _credentials!.address.hex;
    _backedUp = false;
    _sessionUnlocked = true;
    await refreshBalances();
    notifyListeners();
  }

  Future<void> switchWallet(String id) async {
    if (!_wallets.any((w) => w.id == id)) {
      return;
    }
    await _storage.setActiveWalletId(id);
    _activeWalletId = id;
    await _loadCredentialsFromActiveMnemonic();
    if (_credentials != null) {
      await refreshBalances();
    } else {
      notifyListeners();
    }
  }

  Future<void> renameActiveWallet(String name) async {
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _wallets = _wallets
        .map((w) => w.id == id ? w.copyWith(name: trimmed) : w)
        .toList();
    await _storage.writeWalletList(_wallets);
    notifyListeners();
  }

  Future<String?> readMnemonicForBackup() async {
    final id = _activeWalletId;
    if (id == null) {
      return null;
    }
    return _storage.readMnemonicForWallet(id);
  }

  Future<PinVerifyResult> verifyTransactionPin(String pin) =>
      _storage.verifyPin(pin);

  Future<PinVerifyResult> unlockSession(String pin) async {
    final r = await _storage.verifyPin(pin);
    if (r.ok) {
      _sessionUnlocked = true;
      notifyListeners();
    }
    return r;
  }

  void lockSession() {
    if (_pinEnabled) {
      _sessionUnlocked = false;
      notifyListeners();
    }
  }

  Future<void> markBackedUp() async {
    final id = _activeWalletId;
    if (id == null) {
      return;
    }
    await _storage.writeBackedUpForWallet(id, true);
    _wallets = _wallets
        .map((w) => w.id == id ? w.copyWith(backedUp: true) : w)
        .toList();
    _backedUp = true;
    notifyListeners();
  }

  Future<void> refreshBalances() async {
    if (_credentials == null) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      final addr = _credentials!.address;
      final ethBal =
          await _tokenService.getEthBalanceEther(EvmNetworkId.ethereum, addr);
      final baseBal =
          await _tokenService.getEthBalanceEther(EvmNetworkId.base, addr);
      _evmCoins = [
        CoinData(
          id: 'eth_mainnet',
          symbol: 'ETH',
          name: 'Ethereum',
          icon: '⚪',
          network: 'Ethereum',
          chainId: 1,
          price: 0,
          priceChange24h: 0,
          balance: ethBal,
          balanceUSD: 0,
        ),
        CoinData(
          id: 'eth_base',
          symbol: 'ETH',
          name: 'Base',
          icon: '🔵',
          network: 'Base',
          chainId: 8453,
          price: 0,
          priceChange24h: 0,
          balance: baseBal,
          balanceUSD: 0,
        ),
      ];
    } catch (e, st) {
      debugPrint('refreshBalances: $e\n$st');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> sendEth({
    required EvmNetworkId network,
    required String toHex,
    required String amountEther,
  }) async {
    final c = _credentials;
    if (c == null) {
      throw StateError('No wallet');
    }
    return _sendService.sendEth(
      network: network,
      credentials: c,
      toHex: toHex,
      amountEther: amountEther,
    );
  }

  @override
  void dispose() {
    EvmRpcPool.disposeAll();
    super.dispose();
  }
}

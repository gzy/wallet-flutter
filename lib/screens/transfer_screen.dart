import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';

import '../config/evm_environment.dart';
import '../models/evm_network.dart';
import '../providers/wallet_controller.dart';
import '../services/evm/transfer_fee_service.dart';
import '../theme/app_colors.dart';
import '../widgets/pin_verify_sheet.dart';
import 'address_book_screen.dart';

/// 将 RPC 限流、非 JSON 响应等转成可读提示（避免整段 FormatException 糊脸）。
String _mapTransferSendError(Object e) {
  if (e is StateError) {
    final m = e.message;
    if (m.contains('收款') || m.contains('钱包相同') || m.contains('向自己')) {
      return m;
    }
  }
  if (e is ArgumentError) {
    final m = e.message?.toString() ?? '';
    if (m.contains('address') || m.contains('hex')) {
      return '收款地址格式无效，请使用完整的 0x 开头 42 位十六进制地址（不要填 ENS 昵称，除非已做解析）。';
    }
  }
  final s = e.toString();
  if (s.contains('Too many connections') ||
      s.contains('Too Many Requests') ||
      s.contains('429') ||
      s.toLowerCase().contains('rate limit')) {
    return '节点繁忙或限流，请稍后重试；正式使用建议配置自有 RPC（Infura / Alchemy 等）。';
  }
  if (e is FormatException || s.contains('Unexpected character')) {
    return '链上节点返回异常（多为限流或维护），请稍后重试。';
  }
  return '发送失败: $e';
}

String _normalizeAddrField(String raw) {
  return raw.trim().replaceAll(RegExp(r'[\s\n\r]+'), '');
}

class _TokenItem {
  final String symbol;
  final String network;
  final double balance;

  /// 行情 USD 单价（如 ETH 美元价）；无行情时为 0。
  final double priceUsd;
  final Color color;
  final String mark;
  final EvmNetworkId evmNetwork;
  const _TokenItem(
    this.symbol,
    this.network,
    this.balance,
    this.priceUsd,
    this.color,
    this.mark,
    this.evmNetwork,
  );
}

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _usd = TextEditingController();
  int _selectedTokenIndex = 0;

  /// 避免金额 ⇄ USD 互写时递归触发 [TextEditingController] 监听。
  bool _syncingAmountUsd = false;

  static const _transferColors = {
    EvmNetworkId.ethereum: Color(0xFF3B82F6),
    EvmNetworkId.base: Color(0xFF60A5FA),
  };
  static const _transferMarks = {
    EvmNetworkId.ethereum: '◆',
    EvmNetworkId.base: '◉',
  };

  List<_TokenItem> _tokensFor(WalletController w) {
    return EvmEnvironment.nativeCoins.map((cfg) {
      var bal = 0.0;
      var priceUsd = 0.0;
      final cid = EvmEnvironment.chainId(cfg.networkKey);
      if (w.hasWallet) {
        for (final c in w.evmCoins) {
          if (c.chainId == cid) {
            bal = c.balance;
            priceUsd = c.price;
            break;
          }
        }
      }
      return _TokenItem(
        cfg.symbol,
        cfg.networkLabel,
        bal,
        priceUsd,
        _transferColors[cfg.networkKey]!,
        _transferMarks[cfg.networkKey]!,
        cfg.networkKey,
      );
    }).toList();
  }

  double _unitUsdPrice(WalletController w) {
    final tokens = _tokensFor(w);
    if (tokens.isEmpty) {
      return 0;
    }
    return _selectedToken(tokens).priceUsd;
  }

  void _syncUsdFromAmount(WalletController w) {
    if (_syncingAmountUsd || !mounted) {
      return;
    }
    final price = _unitUsdPrice(w);
    if (price <= 0) {
      return;
    }
    final raw = _amount.text.trim();
    if (raw.isEmpty) {
      _syncingAmountUsd = true;
      _usd.clear();
      _syncingAmountUsd = false;
      return;
    }
    final ether = double.tryParse(raw);
    if (ether == null) {
      return;
    }
    _syncingAmountUsd = true;
    _usd.text = (ether * price).toStringAsFixed(2);
    _syncingAmountUsd = false;
  }

  void _syncAmountFromUsd(WalletController w) {
    if (_syncingAmountUsd || !mounted) {
      return;
    }
    final price = _unitUsdPrice(w);
    if (price <= 0) {
      return;
    }
    final raw = _usd.text.trim();
    if (raw.isEmpty) {
      _syncingAmountUsd = true;
      _amount.clear();
      _syncingAmountUsd = false;
      return;
    }
    final usd = double.tryParse(raw);
    if (usd == null) {
      return;
    }
    final ether = usd / price;
    _syncingAmountUsd = true;
    var s = ether.toStringAsFixed(8);
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    _amount.text = s.isEmpty ? '0' : s;
    _syncingAmountUsd = false;
  }

  void _onAmountFieldChanged() {
    if (!mounted) {
      return;
    }
    _syncUsdFromAmount(context.read<WalletController>());
  }

  void _onUsdFieldChanged() {
    if (!mounted) {
      return;
    }
    _syncAmountFromUsd(context.read<WalletController>());
  }

  _TokenItem _selectedToken(List<_TokenItem> tokens) =>
      tokens[_selectedTokenIndex.clamp(0, tokens.length - 1)];

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmountFieldChanged);
    _usd.addListener(_onUsdFieldChanged);
  }

  @override
  void dispose() {
    _amount.removeListener(_onAmountFieldChanged);
    _usd.removeListener(_onUsdFieldChanged);
    _address.dispose();
    _amount.dispose();
    _usd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final tokens = _tokensFor(wallet);
    final sel = _selectedToken(tokens);
    final fromAddr = wallet.addressHex;
    final walletName = wallet.activeWallet?.name.trim();
    final fromWalletLabel = (walletName != null && walletName.isNotEmpty)
        ? walletName
        : (fromAddr != null
            ? '${fromAddr.substring(0, 6)}…${fromAddr.substring(fromAddr.length - 4)}'
            : '未创建钱包');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text('转账', style: TextStyle(fontSize: 22)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _box(
                      child: Row(
                        children: [
                          const CircleAvatar(
                            radius: 11,
                            backgroundColor: Color(0xFF30343A),
                            child: Icon(Icons.description_outlined,
                                size: 13, color: AppColors.textSecondary),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fromWalletLabel,
                              style: const TextStyle(fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _box(
                    child: Text(
                      fromAddr != null
                          ? '${fromAddr.substring(0, 4)}…${fromAddr.substring(fromAddr.length - 4)}'
                          : '—',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 16),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _box(
                child: InkWell(
                  onTap: () => _openTokenPicker(tokens),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: sel.color,
                        child: Text(
                          sel.symbol.substring(0, 1),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sel.symbol,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              sel.network,
                              style: const TextStyle(
                                  fontSize: 15, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('收款地址', style: TextStyle(fontSize: 18)),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(Icons.perm_contact_calendar_outlined,
                        size: 20, color: AppColors.textSecondary),
                    onPressed: () async {
                      final picked = await Navigator.of(context).push<String>(
                        MaterialPageRoute<String>(
                          builder: (_) => AddressBookScreen(
                            symbol: sel.symbol,
                            networkLabel: sel.network,
                          ),
                        ),
                      );
                      if (picked != null && picked.trim().isNotEmpty && mounted) {
                        setState(() => _address.text = picked.trim());
                      }
                    },
                  ),
                  const SizedBox(
                      height: 18,
                      child: VerticalDivider(color: AppColors.borderSoft)),
                  const SizedBox(width: 4),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(Icons.fullscreen,
                        size: 20, color: AppColors.textSecondary),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('全屏输入功能开发中')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _input(_address, '请输入地址、Space ID、ENS...'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: AppColors.borderSoft),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '请确保您的收款地址支持${sel.network}（EVM）网络。',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              _label('金额'),
              _input(_amount, '0.00', suffix: sel.symbol, withMax: true),
              const SizedBox(height: 8),
              _input(_usd, '0.00', suffix: 'USD'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '可用余额: ${sel.balance} ${sel.symbol}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [AppColors.accentStart, AppColors.accentEnd],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openConfirmSheet(tokens),
                      child: const Center(
                        child: Text(
                          '下一步',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.accentText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTokenPicker(List<_TokenItem> tokens) async {
    String searchQuery = '';
    final token = await showModalBottomSheet<_TokenItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final list = tokens.where((t) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return t.symbol.toLowerCase().contains(q) ||
                  t.network.toLowerCase().contains(q);
            }).toList();

            return SafeArea(
              top: false,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.86,
                decoration: const BoxDecoration(
                  color: Color(0xFF181A21),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Row(
                        children: [
                          const Spacer(),
                          const Text('选择币种',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Icon(Icons.close,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3D45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search,
                                color: AppColors.textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                onChanged: (v) =>
                                    setSheetState(() => searchQuery = v.trim()),
                                style: const TextStyle(fontSize: 16),
                                decoration: const InputDecoration(
                                  hintText: '搜索',
                                  hintStyle:
                                      TextStyle(color: AppColors.textMuted),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const Text('粘贴',
                                style: TextStyle(
                                    color: Color(0xFF22D3AA),
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final t = list[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.pop(context, t),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2D35),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 21,
                                    backgroundColor: t.color,
                                    child: Text(
                                      t.mark,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.symbol,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          t.network,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    t.balance == 0
                                        ? '0'
                                        : t.balance.toStringAsFixed(4),
                                    style: const TextStyle(
                                      fontSize: 30,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (token != null) {
      setState(() {
        _selectedTokenIndex = tokens.indexOf(token);
        if (_selectedTokenIndex < 0) _selectedTokenIndex = 0;
      });
      if (mounted) {
        _syncUsdFromAmount(context.read<WalletController>());
      }
    }
  }

  Future<void> _openConfirmSheet(List<_TokenItem> tokens) async {
    final wallet = context.read<WalletController>();
    if (!wallet.hasWallet) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建钱包')),
      );
      return;
    }
    if (_address.text.trim().isEmpty || _amount.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写地址和金额')),
      );
      return;
    }
    final from = wallet.addressHex ?? '';
    final toNorm = _normalizeAddrField(_address.text);
    try {
      final toAddr = EthereumAddress.fromHex(toNorm);
      final fromAddr = EthereumAddress.fromHex(
        from.startsWith('0x') || from.startsWith('0X') ? from : '0x$from',
      );
      if (toAddr.hex.toLowerCase() == fromAddr.hex.toLowerCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('收款地址不能与当前钱包相同，请填写对方地址')),
        );
        return;
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收款地址格式无效，请使用完整 0x 开头的 42 位十六进制地址')),
      );
      return;
    }
    final sel = _selectedToken(tokens);
    final fromShort = from.length > 10
        ? '${from.substring(0, 6)}…${from.substring(from.length - 4)}'
        : from;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _TransferConfirmSheet(
          hostContext: context,
          sheetContext: sheetContext,
          wallet: wallet,
          sel: sel,
          fromShort: fromShort,
          amountStr: _amount.text.trim(),
          recipientDisplay: _address.text,
          toHexNormalized: toNorm,
        );
      },
    );
  }

  Widget _label(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 20),
        ),
      ),
    );
  }

  Widget _box({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF191C22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    String? suffix,
    bool withMax = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF191C22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle:
                    const TextStyle(color: AppColors.textMuted, fontSize: 16),
              ),
            ),
          ),
          if (withMax)
            InkWell(
              onTap: () {
                final w = context.read<WalletController>();
                final tokens = _tokensFor(w);
                final sel = _selectedToken(tokens);
                final b = sel.balance;
                _amount.text = b == 0 ? '0' : b.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
                _syncUsdFromAmount(w);
                setState(() {});
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: const Text('全部', style: TextStyle(fontSize: 14)),
              ),
            ),
          if (suffix != null)
            Text(suffix,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 18)),
          if (controller == _address)
            TextButton(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final t = data?.text?.trim();
                if (t != null && t.isNotEmpty) {
                  setState(() => _address.text = t);
                }
              },
              child: const Text('粘贴',
                  style: TextStyle(color: Color(0xFF22D3AA), fontSize: 18)),
            ),
        ],
      ),
    );
  }
}

Widget _transferConfirmCard({required List<Widget> children}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF222226),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(children: children),
  );
}

Widget _transferKvRow(String left, String right, {bool rightIsAddress = false}) {
  return Row(
    crossAxisAlignment:
        rightIsAddress ? CrossAxisAlignment.start : CrossAxisAlignment.center,
    children: [
      Text(left, style: const TextStyle(color: AppColors.textSecondary)),
      const Spacer(),
      Flexible(
        child: Text(
          right,
          maxLines: rightIsAddress ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    ],
  );
}

class _TransferConfirmSheet extends StatefulWidget {
  const _TransferConfirmSheet({
    required this.hostContext,
    required this.sheetContext,
    required this.wallet,
    required this.sel,
    required this.fromShort,
    required this.amountStr,
    required this.recipientDisplay,
    required this.toHexNormalized,
  });

  final BuildContext hostContext;
  final BuildContext sheetContext;
  final WalletController wallet;
  final _TokenItem sel;
  final String fromShort;
  final String amountStr;
  final String recipientDisplay;
  final String toHexNormalized;

  @override
  State<_TransferConfirmSheet> createState() => _TransferConfirmSheetState();
}

class _TransferConfirmSheetState extends State<_TransferConfirmSheet> {
  static const _gasQuoteRefreshInterval = Duration(seconds: 15);

  Timer? _gasRefreshTimer;
  String _gasLevel = '中';
  double _customGwei = 1;
  final TextEditingController _customGweiController = TextEditingController();

  bool _quoteLoading = true;
  NativeTransferFeeQuote? _resolvedQuote;

  /// [isInitial]：首次打开显示「正在估算」；定时静默刷新不改变加载态，失败时保留上一次报价。
  Future<NativeTransferFeeQuote?> _fetchQuote({required bool isInitial}) async {
    if (!mounted) {
      return _resolvedQuote;
    }
    if (isInitial) {
      setState(() => _quoteLoading = true);
    }
    try {
      final q = await widget.wallet.quoteNativeTransfer(
        network: widget.sel.evmNetwork,
        toHex: widget.toHexNormalized,
        amountEther: widget.amountStr,
      );
      if (!mounted) {
        return q;
      }
      final medGwei = EtherAmount.inWei(
        q.isEip1559 ? q.tipMedWei : (q.legacyGasPriceWei ?? q.tipMedWei),
      ).getValueInUnit(EtherUnit.gwei);
      setState(() {
        _resolvedQuote = q;
        _quoteLoading = false;
        if (_gasLevel != '自定义' && medGwei > 0) {
          _customGwei = medGwei;
        }
      });
      return q;
    } catch (_) {
      if (!mounted) {
        return _resolvedQuote;
      }
      setState(() {
        _quoteLoading = false;
        if (isInitial) {
          _resolvedQuote = null;
        }
      });
      return _resolvedQuote;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_fetchQuote(isInitial: true));
    _gasRefreshTimer = Timer.periodic(_gasQuoteRefreshInterval, (_) {
      unawaited(_fetchQuote(isInitial: false));
    });
  }

  @override
  void dispose() {
    _gasRefreshTimer?.cancel();
    _customGweiController.dispose();
    super.dispose();
  }

  BigInt get _customTipWei {
    final s = _customGwei.toStringAsFixed(9);
    return EtherAmount.fromBase10String(EtherUnit.gwei, s).getInWei;
  }

  String _gasFeeTitle(NativeTransferFeeQuote? quote) {
    if (_quoteLoading) {
      return '正在从节点估算…';
    }
    if (quote == null) {
      return '估算失败，转出时将使用节点默认价';
    }
    final eth = quote.approxMaxEthForLevel(_gasLevel, _customTipWei);
    return '约 ${eth.toStringAsFixed(9)} ETH（${widget.sel.network}，上限）';
  }

  String _usdForLevel(NativeTransferFeeQuote? quote, String level) {
    if (quote == null || widget.sel.priceUsd <= 0) {
      return '—';
    }
    final eth = quote.approxMaxEthForLevel(
      level,
      level == '自定义' ? _customTipWei : BigInt.zero,
    );
    final usd = eth * widget.sel.priceUsd;
    if (usd < 0.01) {
      return '<\$0.01';
    }
    return '\$${usd.toStringAsFixed(2)}';
  }

  Future<void> _openCustomGasDialog() async {
    _customGweiController.text = _customGwei.toStringAsFixed(6);
    final is1559 = _resolvedQuote?.isEip1559 ?? true;
    final value = await showDialog<double>(
      context: widget.sheetContext,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F23),
          title: Text(is1559 ? '自定义优先级费 (Gwei)' : '自定义 gasPrice (Gwei)'),
          content: TextField(
            controller: _customGweiController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '例如 1.5',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final parsed =
                    double.tryParse(_customGweiController.text.trim());
                if (parsed == null || parsed <= 0) {
                  ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                    const SnackBar(content: Text('请输入有效的 Gwei 数值')),
                  );
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    if (value != null) {
      setState(() {
        _gasLevel = '自定义';
        _customGwei = value;
      });
    }
  }

  Widget _gasOption(
    NativeTransferFeeQuote? quote,
    String level, {
    bool isCustom = false,
  }) {
    final isActive = _gasLevel == level;
    final gweiStr = quote == null
        ? '—'
        : quote.gweiLabelForLevel(
            level,
            isCustom ? _customTipWei : BigInt.zero,
          );
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: _quoteLoading
              ? null
              : () {
                  if (isCustom) {
                    _openCustomGasDialog();
                    return;
                  }
                  setState(() => _gasLevel = level);
                },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color:
                  isActive ? const Color(0xFF2F2F36) : const Color(0xFF1B1B1F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive ? AppColors.accent : const Color(0xFF505050),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(level, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  _usdForLevel(quote, level),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.success,
                  ),
                ),
                Text(
                  gweiStr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _resolvedQuote;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('转账', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF222226),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 24,
                    backgroundColor: Color(0xFF2A2A2E),
                    child: Text('🪙'),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.amountStr} ${widget.sel.symbol}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.sel.network,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _transferConfirmCard(
              children: [
                _transferKvRow('付款地址', widget.fromShort),
                const SizedBox(height: 10),
                _transferKvRow(
                  '收款地址',
                  widget.recipientDisplay,
                  rightIsAddress: true,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _transferConfirmCard(
              children: [
                _transferKvRow('矿工费', _gasFeeTitle(quote)),
                const SizedBox(height: 10),
                _transferKvRow('支付方式', 'ETH(${widget.sel.network})'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _gasOption(quote, '低'),
                    _gasOption(quote, '中'),
                    _gasOption(quote, '高'),
                    _gasOption(quote, '自定义', isCustom: true),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(widget.sheetContext),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF5A5A5A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Opacity(
                    opacity: _quoteLoading ? 0.42 : 1,
                    child: SizedBox(
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColors.accentStart,
                              AppColors.accentEnd,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _quoteLoading
                                ? null
                                : () async {
                            Navigator.pop(widget.sheetContext);
                            final messenger =
                                ScaffoldMessenger.of(widget.hostContext);
                            final amountStr = widget.amountStr;
                            final amount = double.tryParse(amountStr);
                            if (amount == null || amount <= 0) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('金额无效')),
                              );
                              return;
                            }
                            final ok = await PinVerifySheet.show(
                              widget.hostContext,
                              title: '确认转账',
                              subtitle: '请输入 6 位 PIN 以授权本次转账。',
                              verify: (pin) => widget.hostContext
                                  .read<WalletController>()
                                  .verifyTransactionPin(pin),
                            );
                            if (ok != true) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('已取消或 PIN 未通过')),
                              );
                              return;
                            }
                            NativeTransferFeeQuote? q = _resolvedQuote;
                            q ??= await _fetchQuote(isInitial: false);
                            final tp = q?.transactionParams(
                              gasLevel: _gasLevel,
                              customPriorityWei: _customTipWei,
                            );
                            try {
                              final hash = await widget.wallet.sendEth(
                                network: widget.sel.evmNetwork,
                                toHex: widget.toHexNormalized,
                                amountEther: amountStr,
                                maxGas: tp?.maxGas,
                                gasPrice: tp?.gasPrice,
                                maxFeePerGas: tp?.maxFeePerGas,
                                maxPriorityFeePerGas: tp?.maxPriorityFeePerGas,
                              );
                              messenger.showSnackBar(
                                SnackBar(content: Text('已广播: $hash')),
                              );
                              await widget.wallet.refreshBalances();
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(_mapTransferSendError(e)),
                                ),
                              );
                            }
                          },
                            child: const Center(
                              child: Text(
                                '转出',
                                style: TextStyle(
                                  color: AppColors.accentText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


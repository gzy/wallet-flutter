import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/coin_data.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import '../services/wallet/wallet_gas_price_service.dart';
import '../services/wallet/wallet_estimate_gas_service.dart';
import '../services/wallet/tron_utils.dart';
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
    return '服务繁忙或限流，请稍后重试。';
  }
  if (e is FormatException || s.contains('Unexpected character')) {
    return '服务端返回异常，请稍后重试。';
  }
  return '发送失败: $e';
}

String _normalizeAddrField(String raw) {
  return raw.trim().replaceAll(RegExp(r'[\s\n\r]+'), '');
}

class _TokenItem {
  final CoinData coin;
  final Color color;
  final String mark;

  const _TokenItem({
    required this.coin,
    required this.color,
    required this.mark,
  });

  String get symbol => coin.symbol;

  String get network => coin.network ?? '—';

  double get balance => coin.balance;

  /// 行情 USD 单价；无行情时为 0。
  double get priceUsd => coin.price;
}

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, this.initialRecipientAddress});

  /// 从交易详情「转账给他/她」进入时预填收款地址（含 `0x`）。
  final String? initialRecipientAddress;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

/// 转账金额相对当前币种余额是否超额（仅 UI 校验，不弹窗）。
String? _transferAmountBalanceError(String amountRaw, _TokenItem sel) {
  final t = amountRaw.trim();
  if (t.isEmpty) {
    return null;
  }
  final v = double.tryParse(t);
  if (v == null || v <= 0) {
    return null;
  }
  if (v > sel.balance + 1e-12) {
    return '转账金额超过可用余额（当前可用 ${sel.balance} ${sel.symbol}）';
  }
  return null;
}

class _TransferScreenState extends State<TransferScreen> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _usd = TextEditingController();
  int _selectedTokenIndex = 0;

  /// 与首页 [WalletScreen] 一致：有当前网络时默认选中该链上的资产，避免仍用全列表第 0 项（常为另一条链、余额 0）。
  bool _syncedInitialChain = false;

  /// 避免金额 ⇄ USD 互写时递归触发 [TextEditingController] 监听。
  bool _syncingAmountUsd = false;

  static const _accentColors = <Color>[
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
    Color(0xFF22D3AA),
    Color(0xFFF59E0B),
    Color(0xFFA78BFA),
  ];

  static const _marks = <String>['◆', '◉', '⬡', '◇', '◈'];

  Color _accentForCoin(CoinData c) {
    final k = c.chainId ?? c.id.hashCode;
    return _accentColors[k.abs() % _accentColors.length];
  }

  String _markForCoin(CoinData c) {
    final k = c.chainId ?? c.id.hashCode;
    return _marks[k.abs() % _marks.length];
  }

  List<_TokenItem> _tokensFor(WalletController w) {
    final out = <_TokenItem>[];
    for (final c in w.evmCoins) {
      out.add(
        _TokenItem(
          coin: c,
          color: _accentForCoin(c),
          mark: _markForCoin(c),
        ),
      );
    }
    return out;
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
    // 刷新「下一步」可用态与超额提示（依赖 [_amount.text]）。
    setState(() {});
  }

  void _onUsdFieldChanged() {
    if (!mounted) {
      return;
    }
    _syncAmountFromUsd(context.read<WalletController>());
    setState(() {});
  }

  _TokenItem _selectedToken(List<_TokenItem> tokens) =>
      tokens[_selectedTokenIndex.clamp(0, tokens.length - 1)];

  static int _indexForSendChain(WalletController w, List<_TokenItem> tokens) {
    if (tokens.isEmpty) {
      return 0;
    }
    final want = w.sendChain;
    if (want == null) {
      return 0;
    }
    for (var i = 0; i < tokens.length; i++) {
      if (w.chainParamForCoin(tokens[i].coin) == want) {
        return i;
      }
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmountFieldChanged);
    _usd.addListener(_onUsdFieldChanged);
    final init = widget.initialRecipientAddress?.trim();
    if (init != null && init.isNotEmpty) {
      _address.text = init.startsWith('0x') ? init : '0x$init';
    }
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
    if (tokens.isNotEmpty && !_syncedInitialChain) {
      _syncedInitialChain = true;
      final idx = _indexForSendChain(wallet, tokens);
      if (idx != _selectedTokenIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          setState(() => _selectedTokenIndex = idx);
          _syncUsdFromAmount(context.read<WalletController>());
        });
      }
    }
    if (tokens.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          title: const Text('转账', style: TextStyle(fontSize: 22)),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '暂无可转账资产：请确认 /api/app/chains 已返回链配置且余额接口可用。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ),
        ),
      );
    }
    final sel = _selectedToken(tokens);
    final amountBalanceErr = _transferAmountBalanceError(_amount.text, sel);
    final canOpenConfirm = amountBalanceErr == null;
    final fromAddr = wallet.addressHex;
    final walletName = wallet.activeWallet?.name.trim();
    final fromWalletLabel = (walletName != null && walletName.isNotEmpty)
        ? walletName
        : (fromAddr != null
            ? '${fromAddr.substring(0, 6)}…${fromAddr.substring(fromAddr.length - 4)}'
            : '未创建钱包');

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: const Text('转账', style: TextStyle(fontSize: 22)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700),
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
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    sel.network,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        color: AppColors.textSecondary),
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
                          constraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
                          icon: const Icon(Icons.perm_contact_calendar_outlined,
                              size: 20, color: AppColors.textSecondary),
                          onPressed: () async {
                            final picked =
                                await Navigator.of(context).push<String>(
                              MaterialPageRoute<String>(
                                builder: (_) => AddressBookScreen(
                                  symbol: sel.symbol,
                                  networkLabel: sel.network,
                                  chainQuery:
                                      wallet.chainParamForCoin(sel.coin),
                                ),
                              ),
                            );
                            if (picked != null &&
                                picked.trim().isNotEmpty &&
                                mounted) {
                              setState(() => _address.text = picked.trim());
                            }
                          },
                        ),
                        const SizedBox(
                            height: 18,
                            child:
                                VerticalDivider(color: AppColors.borderSoft)),
                        const SizedBox(width: 4),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 36, minHeight: 36),
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
                    _input(
                      _amount,
                      '0.00',
                      suffix: sel.symbol,
                      withMax: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 8),
                    _input(
                      _usd,
                      '0.00',
                      suffix: 'USD',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      textInputAction: TextInputAction.done,
                    ),
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
                    if (amountBalanceErr != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        amountBalanceErr,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Opacity(
                opacity: canOpenConfirm ? 1 : 0.45,
                child: SizedBox(
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
                        onTap: canOpenConfirm
                            ? () => _openConfirmSheet(tokens)
                            : null,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTokenPicker(List<_TokenItem> tokens) async {
    if (tokens.isEmpty) {
      return;
    }
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
                          const Text(
                            '选择币种',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                          ),
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
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                ),
                                decoration: const InputDecoration(
                                  hintText: '搜索',
                                  hintStyle:
                                      TextStyle(color: AppColors.textMuted),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const Text(
                              '粘贴',
                              style: TextStyle(
                                color: Color(0xFF22D3AA),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
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
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
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
                                            fontSize: 16,
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          t.network,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w400,
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
                                      fontSize: 15,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w400,
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
    if (tokens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可转账资产')),
      );
      return;
    }
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
    final sel = _selectedToken(tokens);
    if (_transferAmountBalanceError(_amount.text, sel) != null) {
      return;
    }
    final chainQuery = wallet.chainParamForCoin(sel.coin);
    final chainCfg = wallet.backendChains.firstWhere(
      (c) => c.walletApiChainQuery == chainQuery,
      orElse: () => wallet.backendChains.first,
    );
    final isTron = chainCfg.chainType.toUpperCase() == 'TRON';
    final from = (isTron ? wallet.tronAddress : wallet.addressHex) ?? '';
    final toNorm = _normalizeAddrField(_address.text);
    final isToValid = isTron
        ? isValidTronAddress(toNorm)
        : RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(toNorm);
    if (!isToValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTron
                ? '收款地址格式无效，请使用 Tron 的 T... 地址'
                : '收款地址格式无效，请使用完整 0x 开头的 42 位十六进制地址',
          ),
        ),
      );
      return;
    }
    final fromNorm = isTron
        ? from
        : (from.startsWith('0x') || from.startsWith('0X') ? from : '0x$from');
    if (toNorm.toLowerCase() == fromNorm.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收款地址不能与当前钱包相同，请填写对方地址')),
      );
      return;
    }
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
          toAddressNormalized: toNorm,
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
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
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
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              inputFormatters: inputFormatters,
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
                _amount.text = b == 0
                    ? '0'
                    : b.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
                _syncUsdFromAmount(w);
                setState(() {});
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

/// 确认弹窗用：标签独占一行，内容在下方全宽展示，避免窄屏双列把长文案挤成「…」。
Widget _transferKvRow(String left, String right,
    {bool rightIsAddress = false}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        left,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
      const SizedBox(height: 6),
      Text(
        right,
        textAlign: rightIsAddress ? TextAlign.left : TextAlign.right,
        softWrap: true,
        maxLines: rightIsAddress ? 5 : 4,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: rightIsAddress ? 13 : 14,
          height: 1.35,
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
    required this.toAddressNormalized,
  });

  final BuildContext hostContext;
  final BuildContext sheetContext;
  final WalletController wallet;
  final _TokenItem sel;
  final String fromShort;
  final String amountStr;
  final String recipientDisplay;
  final String toAddressNormalized;

  @override
  State<_TransferConfirmSheet> createState() => _TransferConfirmSheetState();
}

class _TransferConfirmSheetState extends State<_TransferConfirmSheet> {
  static const _gasQuoteRefreshInterval = Duration(seconds: 15);

  Timer? _gasRefreshTimer;
  String _gasLevel = '中'; // 低/中/高（对应 slow/medium/fast）
  bool _priceLoading = true;
  bool _limitLoading = true;
  WalletGasPriceQuote? _gasQuote;
  int? _gasLimit;

  WalletGasPriceService get _gasSvc => WalletGasPriceService();
  WalletEstimateGasService get _estimateGasSvc => WalletEstimateGasService();

  String get _chainCode {
    // 与 `/api/app/wallet/gasPrice`、`estimateGas`、`createTransaction` 的 `chain` 参数一致（优先后端 chainCode）。
    return widget.wallet.chainParamForCoin(widget.sel.coin);
  }

  bool get _feeLoading => _priceLoading || _limitLoading;

  Future<void> _refreshFeeData({required bool isInitial}) async {
    if (!mounted) return;
    if (isInitial) {
      setState(() {
        _priceLoading = true;
        _limitLoading = true;
        _gasQuote = null;
        _gasLimit = null;
      });
    }

    final chainCfg = widget.wallet.backendChains.firstWhere(
      (c) => c.walletApiChainQuery == _chainCode,
      orElse: () => widget.wallet.backendChains.first,
    );
    final isTron = chainCfg.chainType.toUpperCase() == 'TRON';
    if (isTron) {
      // Tron 费用/预估走不同体系：先不在确认页展示 EVM 的 gas 估算（避免误导）。
      if (!mounted) return;
      setState(() {
        _gasQuote = null;
        _priceLoading = false;
        _gasLimit = null;
        _limitLoading = false;
      });
      return;
    }

    final qFuture = _gasSvc.fetchGasPrice(chain: _chainCode);
    final owner = widget.wallet.addressHex;
    final amount = double.tryParse(widget.amountStr);
    int? fromApi;
    if (owner == null || owner.isEmpty || amount == null) {
      fromApi = null;
    } else {
      final data = await _estimateGasSvc.estimateGas(
        chain: _chainCode,
        coin: widget.sel.symbol,
        ownerAddress: owner.startsWith('0x') || owner.startsWith('0X')
            ? owner
            : '0x$owner',
        toAddress: widget.toAddressNormalized,
        amount: amount,
      );
      fromApi = WalletEstimateGasService.parseGasLimit(data);
    }

    final q = await qFuture;
    if (!mounted) return;

    setState(() {
      _gasQuote = q;
      _priceLoading = false;
      _gasLimit = fromApi;
      _gasLimit ??= 21000;
      _limitLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refreshFeeData(isInitial: true));
    _gasRefreshTimer = Timer.periodic(_gasQuoteRefreshInterval, (_) {
      unawaited(_refreshFeeData(isInitial: false));
    });
  }

  @override
  void dispose() {
    _gasRefreshTimer?.cancel();
    super.dispose();
  }

  String _gasFeeTitle(WalletGasPriceQuote? quote) {
    if (_feeLoading) {
      return '正在获取矿工费…';
    }
    if (quote == null) {
      return '获取失败，稍后重试';
    }
    // 这里先展示 gwei 档位；并结合 estimateGas 返回的 gasLimit 展示约消耗（以当前币种计）。
    final eth = _feeEthForLevel(quote, _gasLevel);
    if (eth == null) {
      final gwei = _gweiForLevel(quote, _gasLevel);
      return '$gwei Gwei（${widget.sel.network}）';
    }
    return '约 ${eth.toStringAsFixed(8)} ${widget.sel.symbol}（${widget.sel.network}）';
  }

  String _gweiForLevel(WalletGasPriceQuote quote, String level) {
    switch (level) {
      case '低':
        return quote.slowGasPriceGwei.toString();
      case '高':
        return quote.fastGasPriceGwei.toString();
      case '中':
      default:
        return quote.mediumGasPriceGwei.toString();
    }
  }

  String _usdForLevel(WalletGasPriceQuote? quote, String level) {
    if (quote == null || widget.sel.priceUsd <= 0) {
      return '—';
    }
    final eth = _feeEthForLevel(quote, level);
    if (eth == null) {
      return '—';
    }
    final usd = eth * widget.sel.priceUsd;
    if (usd < 0.01) {
      return '<\$0.01';
    }
    return '\$${usd.toStringAsFixed(2)}';
  }

  double? _feeEthForLevel(WalletGasPriceQuote quote, String level) {
    if (_gasLimit == null) return null;
    // feeEth ≈ gasPriceGwei * 1e9 * gasLimit / 1e18 = gasPriceGwei * gasLimit / 1e9
    final gweiStr = _gweiForLevel(quote, level);
    final gwei = double.tryParse(gweiStr);
    if (gwei == null || gwei <= 0) return null;
    return (gwei * _gasLimit!) / 1e9;
  }

  Widget _gasCell(
    WalletGasPriceQuote? quote,
    String level,
  ) {
    final isActive = _gasLevel == level;
    final gweiStr = quote == null ? '—' : _gweiForLevel(quote, level);
    return InkWell(
      onTap: _feeLoading
          ? null
          : () {
              setState(() => _gasLevel = level);
            },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF2F2F36) : const Color(0xFF1B1B1F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? AppColors.accent : const Color(0xFF505050),
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              level,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _usdForLevel(quote, level),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              gweiStr == '—' ? '—' : '$gweiStr Gwei',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = _gasQuote;
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
                _transferKvRow(
                  '支付方式',
                  '${widget.sel.symbol}（${widget.sel.network}）',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _gasCell(quote, '低')),
                    const SizedBox(width: 8),
                    Expanded(child: _gasCell(quote, '中')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _gasCell(quote, '高')),
                    const SizedBox(width: 8),
                    const Expanded(child: SizedBox()),
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
                    opacity: _feeLoading ? 0.42 : 1,
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
                            onTap: _feeLoading
                                ? null
                                : () async {
                                    final messenger = ScaffoldMessenger.of(
                                        widget.hostContext);
                                    final host = widget.hostContext;
                                    final wc = host.read<WalletController>();
                                    final amountStr = widget.amountStr;
                                    final amount = double.tryParse(amountStr);
                                    if (amount == null || amount <= 0) {
                                      messenger.showSnackBar(
                                        const SnackBar(content: Text('金额无效')),
                                      );
                                      return;
                                    }
                                    if (_transferAmountBalanceError(
                                            amountStr, widget.sel) !=
                                        null) {
                                      Navigator.pop(widget.sheetContext);
                                      return;
                                    }
                                    Navigator.pop(widget.sheetContext);
                                    final ok = await PinVerifySheet.show(
                                      host,
                                      title: '确认转账',
                                      subtitle: '请输入 6 位 PIN 以授权本次转账。',
                                      verify: (pin) =>
                                          wc.verifyTransactionPin(pin),
                                    );
                                    if (ok != true) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                            content: Text('已取消或 PIN 未通过')),
                                      );
                                      return;
                                    }
                                    final owner = widget.wallet.addressHex;
                                    if (owner == null || owner.isEmpty) {
                                      messenger.showSnackBar(
                                        const SnackBar(content: Text('钱包地址为空')),
                                      );
                                      return;
                                    }
                                    final gasPriceType = switch (_gasLevel) {
                                      '低' => 'slow',
                                      '高' => 'fast',
                                      _ => 'medium',
                                    };
                                    if (!host.mounted) {
                                      return;
                                    }
                                    var loadingOpen = false;
                                    void closeLoading() {
                                      if (!loadingOpen || !host.mounted) {
                                        return;
                                      }
                                      loadingOpen = false;
                                      Navigator.of(host, rootNavigator: true)
                                          .pop();
                                    }

                                    showDialog<void>(
                                      context: host,
                                      barrierDismissible: false,
                                      builder: (ctx) => const Center(
                                        child: Card(
                                          color: Color(0xE6222226),
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 22, vertical: 18),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppColors.accent,
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Text(
                                                  '正在广播交易…',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textPrimary,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    loadingOpen = true;
                                    try {
                                      if (!host.mounted) {
                                        return;
                                      }
                                      final hash = await wc
                                          .createSignBroadcastBackendTransfer(
                                        chain: _chainCode,
                                        coin: widget.sel.symbol,
                                        toAddress: widget.toAddressNormalized,
                                        amount: double.parse(amountStr),
                                        gasPriceType: gasPriceType,
                                      );
                                      closeLoading();
                                      unawaited(
                                          wc.recordRecentTransferRecipient(
                                        chain: _chainCode,
                                        address: widget.toAddressNormalized,
                                      ));
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('已广播: $hash')),
                                      );
                                      await wc.refreshBalances();
                                      if (!host.mounted) {
                                        return;
                                      }
                                      Navigator.of(host).pop();
                                    } catch (e) {
                                      closeLoading();
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content:
                                              Text(_mapTransferSendError(e)),
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

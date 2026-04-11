import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:web3dart/web3dart.dart';

import '../config/evm_environment.dart';
import '../models/evm_network.dart';
import '../providers/wallet_controller.dart';
import '../services/wallet/secure_storage_service.dart';
import '../theme/app_colors.dart';

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
  final Color color;
  final String mark;
  final EvmNetworkId evmNetwork;
  const _TokenItem(
    this.symbol,
    this.network,
    this.balance,
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
  final TextEditingController _customGweiController = TextEditingController();
  int _selectedTokenIndex = 0;
  String _gasLevel = '中';
  double _customGwei = 0.040084;

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
      final cid = EvmEnvironment.chainId(cfg.networkKey);
      if (w.hasWallet) {
        for (final c in w.evmCoins) {
          if (c.chainId == cid) {
            bal = c.balance;
            break;
          }
        }
      }
      return _TokenItem(
        cfg.symbol,
        cfg.networkLabel,
        bal,
        _transferColors[cfg.networkKey]!,
        _transferMarks[cfg.networkKey]!,
        cfg.networkKey,
      );
    }).toList();
  }

  _TokenItem _selectedToken(List<_TokenItem> tokens) =>
      tokens[_selectedTokenIndex.clamp(0, tokens.length - 1)];

  @override
  void dispose() {
    _address.dispose();
    _amount.dispose();
    _usd.dispose();
    _customGweiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletController>();
    final tokens = _tokensFor(wallet);
    final sel = _selectedToken(tokens);
    final fromAddr = wallet.addressHex;

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
                              fromAddr != null
                                  ? '${fromAddr.substring(0, 6)}…${fromAddr.substring(fromAddr.length - 4)}'
                                  : '未创建钱包',
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
              const Row(
                children: [
                  Text('收款地址', style: TextStyle(fontSize: 18)),
                  Spacer(),
                  Icon(Icons.perm_contact_calendar_outlined,
                      size: 20, color: AppColors.textSecondary),
                  SizedBox(width: 12),
                  SizedBox(
                      height: 18,
                      child: VerticalDivider(color: AppColors.borderSoft)),
                  SizedBox(width: 12),
                  Icon(Icons.fullscreen,
                      size: 20, color: AppColors.textSecondary),
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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                                '${_amount.text} ${sel.symbol}',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                sel.network,
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _confirmCard(
                      children: [
                        _kvRow('付款地址', fromShort),
                        const SizedBox(height: 10),
                        _kvRow('收款地址', _address.text, rightIsAddress: true),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _confirmCard(
                      children: [
                        _kvRow('矿工费', _gasFeeText(sel.evmNetwork)),
                        const SizedBox(height: 10),
                        _kvRow('支付方式', 'ETH(${sel.network})'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _gasOption('低', '<\$0.01', '0.0240504 Gwei',
                                setSheetState),
                            _gasOption(
                                '中', '<\$0.01', '0.040084 Gwei', setSheetState),
                            _gasOption('高', '<\$0.01', '0.0440924 Gwei',
                                setSheetState),
                            _gasOption(
                              '自定义',
                              '',
                              '${_customGwei.toStringAsFixed(6)} Gwei',
                              setSheetState,
                              isCustom: true,
                            ),
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
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: Color(0xFF5A5A5A)),
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
                          child: SizedBox(
                            height: 48,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    AppColors.accentStart,
                                    AppColors.accentEnd
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    final messenger =
                                        ScaffoldMessenger.of(this.context);
                                    final amountStr = _amount.text.trim();
                                    final amount = double.tryParse(amountStr);
                                    if (amount == null || amount <= 0) {
                                      messenger.showSnackBar(const SnackBar(
                                          content: Text('金额无效')));
                                      return;
                                    }
                                    // 每次转账都要求输入 PIN（会话解锁不等同于授权转账）
                                    final ok = await _PinSheet.show(
                                      this.context,
                                      title: '确认转账',
                                      subtitle: '请输入 6 位 PIN 以授权本次转账。',
                                      verify: (pin) => this
                                          .context
                                          .read<WalletController>()
                                          .verifyTransactionPin(pin),
                                    );
                                    if (ok != true) {
                                      messenger.showSnackBar(const SnackBar(
                                          content: Text('已取消或 PIN 未通过')));
                                      return;
                                    }
                                    try {
                                      final hash = await wallet.sendEth(
                                        network: sel.evmNetwork,
                                        toHex: _normalizeAddrField(_address.text),
                                        amountEther: amountStr,
                                      );
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('已广播: $hash')),
                                      );
                                      await wallet.refreshBalances();
                                    } catch (e) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                            content:
                                                Text(_mapTransferSendError(e))),
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
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
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

  Widget _confirmCard({required List<Widget> children}) {
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

  Widget _kvRow(String left, String right, {bool rightIsAddress = false}) {
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

  Widget _gasOption(
    String level,
    String price,
    String gwei,
    void Function(void Function()) setSheetState, {
    bool isCustom = false,
  }) {
    final isActive = _gasLevel == level;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: () {
            if (isCustom) {
              _openCustomGasDialog(setSheetState);
              return;
            }
            setSheetState(() => _gasLevel = level);
            setState(() => _gasLevel = level);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            decoration: BoxDecoration(
              color:
                  isActive ? const Color(0xFF2F2F36) : const Color(0xFF1B1B1F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive ? AppColors.accent : const Color(0xFF505050),
              ),
            ),
            child: Column(
              children: [
                Text(level, style: const TextStyle(fontSize: 12)),
                if (!isCustom) ...[
                  const SizedBox(height: 2),
                  Text(price,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.success)),
                  Text(gwei,
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textSecondary)),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    gwei,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _gasFeeText(EvmNetworkId net) {
    final netLabel = net == EvmNetworkId.ethereum ? 'Ethereum' : 'Base';
    if (_gasLevel == '低') return '约 0.000000505 ETH ($netLabel，估算)';
    if (_gasLevel == '中') return '约 0.000000842 ETH ($netLabel，估算)';
    if (_gasLevel == '高') return '约 0.000001009 ETH ($netLabel，估算)';
    final estimated = _customGwei * 0.000021;
    return '${estimated.toStringAsFixed(9)} ETH ($netLabel，估算)';
  }

  Future<void> _openCustomGasDialog(
    void Function(void Function()) setSheetState,
  ) async {
    _customGweiController.text = _customGwei.toStringAsFixed(6);
    final value = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1F1F23),
          title: const Text('自定义 Gas (Gwei)'),
          content: TextField(
            controller: _customGweiController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '例如 0.040084',
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
                  ScaffoldMessenger.of(this.context).showSnackBar(
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
      setSheetState(() {
        _gasLevel = '自定义';
      });
      setState(() {
        _gasLevel = '自定义';
        _customGwei = value;
      });
    }
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: const Text('全部', style: TextStyle(fontSize: 14)),
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

class _PinSheet extends StatefulWidget {
  const _PinSheet({
    required this.title,
    required this.subtitle,
    required this.verify,
  });

  final String title;
  final String subtitle;
  final Future<PinVerifyResult> Function(String pin) verify;

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Future<PinVerifyResult> Function(String pin) verify,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) =>
          _PinSheet(title: title, subtitle: subtitle, verify: verify),
    );
  }

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  String _pin = '';
  bool _busy = false;

  Future<void> _tap(String n) async {
    if (_pin.length >= 6 || _busy) return;
    setState(() => _pin = '$_pin$n');
    if (_pin.length != 6) return;

    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final r = await widget.verify(_pin);
    if (!mounted) return;
    if (!r.ok) {
      final msg = r.lockedSeconds != null && r.lockedSeconds! > 0
          ? 'PIN 已锁定，请 ${r.lockedSeconds}s 后再试'
          : (r.remainingAttempts != null
              ? 'PIN 不正确，还可尝试 ${r.remainingAttempts} 次'
              : 'PIN 不正确');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() {
        _pin = '';
        _busy = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  void _delete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Spacer(),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon:
                        const Icon(Icons.close, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: filled
                            ? AppColors.textPrimary
                            : AppColors.borderSoft,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: filled
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.textPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  );
                }),
              ),
              const SizedBox(height: 18),
              _KeyRow(keys: const ['1', '2', '3'], onTap: _tap),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['4', '5', '6'], onTap: _tap),
              const SizedBox(height: 10),
              _KeyRow(keys: const ['7', '8', '9'], onTap: _tap),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 88, height: 54),
                  _KeyButton(label: '0', onTap: () => _tap('0')),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    height: 54,
                    child: TextButton(
                      onPressed: _delete,
                      child: const Icon(Icons.backspace_outlined,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  final List<String> keys;
  final ValueChanged<String> onTap;
  const _KeyRow({required this.keys, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final k in keys) ...[
          _KeyButton(label: k, onTap: () => onTap(k)),
          if (k != keys.last) const SizedBox(width: 12),
        ]
      ],
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _KeyButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 88,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

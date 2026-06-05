import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/tron_account_resource_vo.dart';
import '../models/tron_resource_order_type.dart';
import '../models/tron_resource_preorder_dto.dart';
import '../models/tron_resource_price_tier.dart';
import '../providers/wallet_controller.dart';
import '../services/wallet/tron_resource_service.dart';
import 'tron_energy_receive_address_sheet.dart';
import '../services/wallet/tron_utils.dart';
import '../theme/app_colors.dart';
import '../widgets/coin_icon.dart';
import 'backend_float/backend_float_window_capsule_bar.dart';
import 'pin_verify_sheet.dart';

/// 能量租赁页局部色（对齐设计稿紫色调 + #1C1C1E 卡片）。
abstract final class _RentUi {
  static const card = Color(0xFF1C1C1E);
  static const divider = Color(0xFF2E2E32);
  static const purple = Color(0xFF8B7CFF);
  static const btnGradientStart = Color(0xFF7E74FF);
  static const btnGradientEnd = Color(0xFF5E56F0);
  static const labelGrey = Color(0xFF8E8E93);
  static const rowMinHeight = 52.0;
  static const cardRadius = 12.0;
  static const hPad = 16.0;
  static const sectionGap = 16.0;
}

/// UI 租赁方式 ↔ 后台 [TronResourceOrderType]。
enum _RentMode {
  buyNum,
  quickRent,
}

extension _RentModeX on _RentMode {
  String get orderType => switch (this) {
        _RentMode.buyNum => TronResourceOrderType.buyNum,
        _RentMode.quickRent => TronResourceOrderType.quickRent,
      };

  bool get isBuyNum => this == _RentMode.buyNum;
}

/// 能量租赁展开面板内的原生表单。
class TronEnergyRentalPanel extends StatefulWidget {
  const TronEnergyRentalPanel({
    super.key,
    required this.chainQuery,
    required this.symbol,
    required this.networkLabel,
    required this.onMinimize,
    required this.onClose,
    required this.onShowMoreMenu,
  });

  final String chainQuery;
  final String symbol;
  final String networkLabel;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onShowMoreMenu;

  @override
  State<TronEnergyRentalPanel> createState() => _TronEnergyRentalPanelState();
}

class _TronEnergyRentalPanelState extends State<TronEnergyRentalPanel> {
  final _resourceService = TronResourceService();
  final _countController = TextEditingController(
    text: '${TronResourceOrderType.buyNumMinCount}',
  );

  _RentMode _mode = _RentMode.buyNum;
  TronAccountResourceVo? _resource;
  List<TronResourcePriceTier> _tiers = [];
  TronResourcePriceTier? _selectedTier;
  String _toAddress = '';
  String _walletLabel = '';
  bool _loadingResource = true;
  bool _loadingPrice = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final wc = context.read<WalletController>();
    final addr = wc.tronAddress?.trim() ?? '';
    _toAddress = addr;
    _walletLabel = wc.activeWallet?.name ?? '钱包';
    await Future.wait([_loadResource(), _loadPrice()]);
  }

  Future<void> reload() async {
    await Future.wait([_loadResource(), _loadPrice()]);
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _loadResource() async {
    final wc = context.read<WalletController>();
    final addr = wc.tronAddress?.trim();
    if (addr == null || addr.isEmpty) {
      setState(() {
        _loadingResource = false;
        _error = 'Tron 地址未就绪';
      });
      return;
    }
    setState(() => _loadingResource = true);
    final r = await _resourceService.fetchAccountResource(addr);
    if (!mounted) return;
    setState(() {
      _resource = r;
      _loadingResource = false;
    });
  }

  Future<void> _loadPrice() async {
    setState(() => _loadingPrice = true);
    final tiers = await _resourceService.fetchPrice(_mode.orderType);
    if (!mounted) return;
    setState(() {
      _tiers = tiers;
      _loadingPrice = false;
      _selectedTier = tiers.isNotEmpty ? tiers.first : null;
    });
  }

  Future<void> _onModeChanged(_RentMode mode) async {
    if (_mode == mode) return;
    if (mode == _RentMode.buyNum) {
      final c = int.tryParse(_countController.text.trim()) ?? 0;
      if (c < TronResourceOrderType.buyNumMinCount) {
        _countController.text = '${TronResourceOrderType.buyNumMinCount}';
      }
    }
    setState(() => _mode = mode);
    await _loadPrice();
  }

  int get _orderCount {
    if (!_mode.isBuyNum) return TronResourceOrderType.quickRentCount;
    final c = int.tryParse(_countController.text.trim()) ?? 0;
    if (c < TronResourceOrderType.buyNumMinCount) return 0;
    return c;
  }

  double get _estimatedPrice {
    final tier = _selectedTier;
    if (tier == null) return 0;
    if (_mode.isBuyNum) {
      if (_orderCount <= 0) return 0;
      return tier.price * _orderCount;
    }
    return tier.price;
  }

  /// 价格未算出（如未填笔数）时不展示付款卡片。
  bool get _showPaymentSection =>
      !_loadingPrice && _selectedTier != null && _estimatedPrice > 0;

  double _trxBalance(WalletController wc) {
    for (final c in wc.evmCoins) {
      if (c.symbol.toUpperCase() == 'TRX') {
        return c.balance;
      }
    }
    return 0;
  }

  bool _canPay(double trxBalance) {
    if (_submitting || _loadingPrice || _selectedTier == null) return false;
    if (_estimatedPrice <= 0) return false;
    if (trxBalance < _estimatedPrice) return false;
    if (!isValidTronAddress(_toAddress.trim())) return false;
    if (_mode.isBuyNum && _orderCount < TronResourceOrderType.buyNumMinCount) {
      return false;
    }
    return true;
  }

  Future<void> _pickAddress() async {
    final result = await showTronEnergyReceiveAddressSheet(
      context: context,
      chainQuery: widget.chainQuery,
      symbol: widget.symbol,
      networkLabel: widget.networkLabel,
      initialAddress: _toAddress,
      initialLabel: _walletLabel,
    );
    if (!mounted || result == null) return;
    setState(() {
      _toAddress = result.address;
      _walletLabel = result.label;
    });
  }

  Future<void> _submit() async {
    final wc = context.read<WalletController>();
    final payer = wc.tronAddress?.trim() ?? '';
    final to = _toAddress.trim();
    final tier = _selectedTier;
    final trxBalance = _trxBalance(wc);

    if (!_canPay(trxBalance)) {
      if (trxBalance < _estimatedPrice) {
        _snack('TRX 余额不足');
      }
      return;
    }

    if (payer.isEmpty) {
      _snack('Tron 钱包未初始化');
      return;
    }
    if (!isValidTronAddress(to)) {
      _snack('收款地址无效');
      return;
    }
    if (tier == null) {
      _snack('价格未加载');
      return;
    }

    final count = _orderCount;
    if (_mode.isBuyNum && count < TronResourceOrderType.buyNumMinCount) {
      _snack('笔数套餐最少购买 ${TronResourceOrderType.buyNumMinCount} 笔');
      return;
    }

    final ok = await PinVerifySheet.show(
      context,
      title: '确认能量租赁',
      subtitle: '请输入 6 位 PIN 以授权本次租赁。',
      verify: wc.verifyTransactionPin,
    );
    if (ok != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      final dto = TronResourcePreOrderDto(
        energyType: _mode.orderType,
        resourceValue: tier.resourceValue,
        payerAddress: payer,
        toAddress: to,
        count: count,
      );
      final result = await wc.rentTronEnergy(dto);
      if (!mounted) return;
      await _loadResource();
      final hash = result.txHash ?? '';
      _snack(hash.isEmpty ? '租赁成功' : '租赁成功：$hash');
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('StateError: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _shortAddr(String a) {
    final t = a.trim();
    if (t.length <= 14) return t;
    return '${t.substring(0, 5)}...${t.substring(t.length - 5)}';
  }

  static String _formatTrxAmount(double v) {
    if (v == 0) return '0';
    final t = v.toStringAsFixed(4);
    return t
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatTrxBalance(double v) {
    if (v == 0) return '0';
    var t = v.toStringAsFixed(6);
    t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final trxBalance = _trxBalance(wc);
    final insufficient = _estimatedPrice > 0 && trxBalance < _estimatedPrice;
    final canPay = _canPay(trxBalance);

    final energy = _resource;
    final ea = energy?.energyAvailable ?? 0;
    final el = energy?.energyLimit ?? 0;
    final ba = energy?.bandwidthAvailable ?? 0;
    final bl = energy?.bandwidthLimit ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _headerBar(),
        Expanded(
          child: GestureDetector(
            onTap: _dismissKeyboard,
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                _RentUi.hPad,
                4,
                _RentUi.hPad,
                12,
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(
                  title: '我的资源',
                  trailing: const Text(
                    '教程',
                    style: TextStyle(
                      color: _RentUi.purple,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _card(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: _resourceMetric('能量', '$ea/$el'),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: _resourceMetric('带宽', '$ba/$bl'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loadingResource)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: _RentUi.purple,
                    ),
                  ),
                const SizedBox(height: _RentUi.sectionGap),
                _sectionHeader(
                  title: '资源租赁',
                  trailing: IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.history_rounded,
                      color: _RentUi.labelGrey,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _card(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Column(
                    children: [
                      _modeRadio(
                        label: '笔数套餐',
                        selected: _mode.isBuyNum,
                        onTap: () => _onModeChanged(_RentMode.buyNum),
                      ),
                      const SizedBox(height: 12),
                      _modeRadio(
                        label: '快速租用',
                        selected: _mode == _RentMode.quickRent,
                        onTap: () => _onModeChanged(_RentMode.quickRent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _card(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (_mode.isBuyNum)
                        _transferCountRow()
                      else
                        _quickRentEnergySection(),
                      _insetDivider(),
                      _addressRow(),
                    ],
                  ),
                ),
                if (_showPaymentSection) ...[
                  const SizedBox(height: 8),
                  _card(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _paymentAmountRow(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TRX 余额: ${_formatTrxBalance(trxBalance)}',
                                style: const TextStyle(
                                  color: _RentUi.labelGrey,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
                              ),
                              if (insufficient) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  '余额不足',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
        _payButton(canPay: canPay),
      ],
    );
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _RentUi.card,
        borderRadius: BorderRadius.circular(_RentUi.cardRadius),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: child,
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        trailing,
      ],
    );
  }

  Widget _insetDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Divider(
        height: 1,
        thickness: 1,
        color: _RentUi.divider,
      ),
    );
  }

  Widget _transferCountRow() {
    return SizedBox(
      height: _RentUi.rowMinHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '转账笔数',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.right,
              cursorColor: _RentUi.purple,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              onEditingComplete: _dismissKeyboard,
              onSubmitted: (_) => _dismissKeyboard(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '最少${TronResourceOrderType.buyNumMinCount}笔',
                hintStyle: TextStyle(color: _RentUi.labelGrey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单笔 TRC20 转账常见能量消耗，用于估算「大概可做 N 笔交易」。
  static const int _energyPerTxEstimate = 65000;

  static String _formatCompactEnergy(int n) {
    if (n >= 1000000) {
      final m = n / 1000000;
      return m == m.roundToDouble()
          ? '${m.toInt()}M'
          : '${m.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
    }
    if (n >= 1000) {
      final k = n / 1000;
      return k == k.roundToDouble()
          ? '${k.toInt()}k'
          : '${k.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}k';
    }
    return n.toString();
  }

  int _estimatedTxCount(TronResourcePriceTier tier) {
    final fromApi = tier.transferCount;
    if (fromApi != null && fromApi > 0) return fromApi;
    final e = tier.resourceValue;
    if (e <= 0) return 0;
    return (e / _energyPerTxEstimate).ceil();
  }

  String _quickRentHint(TronResourcePriceTier? tier) {
    if (tier == null) return '';
    final n = _estimatedTxCount(tier);
    if (n <= 0) return '';
    return '大概可以做$n笔交易';
  }

  Widget _quickRentEnergySection() {
    final tier = _selectedTier;

    if (_loadingPrice) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _RentUi.purple,
            ),
          ),
        ),
      );
    }

    if (_tiers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '暂无能量档位',
          style: TextStyle(color: _RentUi.labelGrey, fontSize: 14),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _RentUi.rowMinHeight,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '能量数量',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  tier == null ? '—' : '${tier.resourceValue}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _tiers.map((t) {
              final selected =
                  _selectedTier?.resourceValue == t.resourceValue;
              return _energyPresetChip(
                tier: t,
                selected: selected,
                onTap: () => setState(() => _selectedTier = t),
              );
            }).toList(),
          ),
          if (tier != null) ...[
            const SizedBox(height: 10),
            Text(
              _quickRentHint(tier),
              style: const TextStyle(
                color: _RentUi.labelGrey,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _energyPresetChip({
    required TronResourcePriceTier tier,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _RentUi.purple : const Color(0xFF3A3A3E),
              width: 1,
            ),
            color: selected
                ? _RentUi.purple.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Text(
            _formatCompactEnergy(tier.resourceValue),
            style: TextStyle(
              color: selected ? _RentUi.purple : AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _addressRow() {
    return InkWell(
      onTap: _pickAddress,
      child: SizedBox(
        height: _RentUi.rowMinHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '收款地址',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text.rich(
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _walletLabel,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_toAddress.trim().isNotEmpty)
                        TextSpan(
                          text: ' ${_shortAddr(_toAddress)}',
                          style: const TextStyle(
                            color: _RentUi.labelGrey,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: _RentUi.labelGrey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentAmountRow() {
    final price = _estimatedPrice;
    return SizedBox(
      height: _RentUi.rowMinHeight,
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '付款金额',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (_loadingPrice)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _RentUi.purple,
              ),
            )
          else ...[
            const CoinIcon(symbol: 'TRX', size: 24),
            const SizedBox(width: 8),
            Text(
              price > 0 ? '${_formatTrxAmount(price)} TRX' : '— TRX',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _payButton({required bool canPay}) {
    final enabled = canPay && !_submitting;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _RentUi.hPad,
        8,
        _RentUi.hPad,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SizedBox(
        height: 50,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: enabled
                ? const LinearGradient(
                    colors: [
                      _RentUi.btnGradientStart,
                      _RentUi.btnGradientEnd,
                    ],
                  )
                : null,
            color: enabled ? null : const Color(0xFF2C2C30),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? _submit : null,
              borderRadius: BorderRadius.circular(25),
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        '付款',
                        style: TextStyle(
                          color: enabled
                              ? Colors.white
                              : const Color(0xFF6B6B70),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              '能量租赁',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: widget.onMinimize,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  color: AppColors.textPrimary,
                ),
                BackendFloatWindowCapsuleBar(
                  onMore: widget.onShowMoreMenu,
                  onMinimize: widget.onMinimize,
                  onClose: widget.onClose,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceMetric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _RentUi.labelGrey,
            fontSize: 13,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
      ],
    );
  }

  Widget _modeRadio({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? _RentUi.purple : const Color(0xFF48484A),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppColors.textPrimary
                      : const Color(0xFFD1D1D6),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

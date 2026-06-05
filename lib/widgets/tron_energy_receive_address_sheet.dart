import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_controller.dart';
import '../screens/address_book_screen.dart';
import '../screens/address_qr_scan_screen.dart';
import '../services/wallet/tron_utils.dart';
import '../theme/app_colors.dart';

/// 能量租赁 — 选择收款地址弹窗的返回结果。
class TronEnergyReceiveAddressResult {
  const TronEnergyReceiveAddressResult({
    required this.address,
    required this.label,
  });

  final String address;
  final String label;
}

/// 与 [tron_energy_rental_panel] 设计稿一致的收款地址选择底部弹窗。
Future<TronEnergyReceiveAddressResult?> showTronEnergyReceiveAddressSheet({
  required BuildContext context,
  required String chainQuery,
  required String symbol,
  required String networkLabel,
  required String initialAddress,
  required String initialLabel,
}) {
  return showModalBottomSheet<TronEnergyReceiveAddressResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TronEnergyReceiveAddressSheet(
      chainQuery: chainQuery,
      symbol: symbol,
      networkLabel: networkLabel,
      initialAddress: initialAddress,
      initialLabel: initialLabel,
    ),
  );
}

abstract final class _SheetUi {
  static const sheetBg = Color(0xFF1C1C1E);
  static const fieldBg = Color(0xFF2A2A2E);
  static const purple = Color(0xFF7E74FF);
  static const purpleEnd = Color(0xFF5E56F0);
  static const green = Color(0xFF22D3AA);
  static const labelGrey = Color(0xFF8E8E93);
}

enum _AddressSource { currentWallet, otherWallet }

class _TronEnergyReceiveAddressSheet extends StatefulWidget {
  const _TronEnergyReceiveAddressSheet({
    required this.chainQuery,
    required this.symbol,
    required this.networkLabel,
    required this.initialAddress,
    required this.initialLabel,
  });

  final String chainQuery;
  final String symbol;
  final String networkLabel;
  final String initialAddress;
  final String initialLabel;

  @override
  State<_TronEnergyReceiveAddressSheet> createState() =>
      _TronEnergyReceiveAddressSheetState();
}

class _TronEnergyReceiveAddressSheetState
    extends State<_TronEnergyReceiveAddressSheet> {
  late _AddressSource _source;
  late final TextEditingController _otherController;
  String _otherLabel = '';

  @override
  void initState() {
    super.initState();
    final wc = context.read<WalletController>();
    final current = wc.tronAddress?.trim() ?? '';
    final init = widget.initialAddress.trim();
    final useCurrent =
        init.isEmpty || (current.isNotEmpty && init == current);
    _source =
        useCurrent ? _AddressSource.currentWallet : _AddressSource.otherWallet;
    _otherController = TextEditingController(
      text: useCurrent ? '' : init,
    );
    _otherLabel = useCurrent ? '' : widget.initialLabel;
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String _shortAddr(String a) {
    final t = a.trim();
    if (t.length <= 14) return t;
    return '${t.substring(0, 5)}...${t.substring(t.length - 5)}';
  }

  Future<void> _pasteOther() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t != null && t.isNotEmpty) {
      setState(() {
        _otherController.text = t;
        _otherLabel = _shortAddr(t);
      });
    }
  }

  Future<void> _openAddressBook() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AddressBookScreen(
          symbol: widget.symbol,
          networkLabel: widget.networkLabel,
          chainQuery: widget.chainQuery,
        ),
      ),
    );
    if (!mounted) return;
    if (picked != null && picked.trim().isNotEmpty) {
      final addr = picked.trim();
      setState(() {
        _otherController.text = addr;
        _otherLabel = _shortAddr(addr);
      });
    }
  }

  Future<void> _scanQr() async {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前平台不支持相机扫码，请使用 Android、iOS 或 macOS 客户端。'),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AddressQrScanScreen()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    final field = normalizeAddressFromQrPayload(scanned).trim();
    if (field.isEmpty) return;
    setState(() {
      _otherController.text = field;
      _otherLabel = _shortAddr(field);
    });
    if (!isValidTronAddress(field)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('扫描内容可能不是有效的 Tron 地址，请核对')),
      );
    }
  }

  void _confirm() {
    final wc = context.read<WalletController>();
    if (_source == _AddressSource.currentWallet) {
      final addr = wc.tronAddress?.trim() ?? '';
      if (addr.isEmpty || !isValidTronAddress(addr)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前钱包 Tron 地址不可用')),
        );
        return;
      }
      Navigator.pop(
        context,
        TronEnergyReceiveAddressResult(
          address: addr,
          label: wc.activeWallet?.name ?? '当前钱包',
        ),
      );
      return;
    }

    final addr = _otherController.text.trim();
    if (!isValidTronAddress(addr)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的 Tron 收款地址')),
      );
      return;
    }
    final label = _otherLabel.trim().isNotEmpty
        ? _otherLabel.trim()
        : _shortAddr(addr);
    Navigator.pop(
      context,
      TronEnergyReceiveAddressResult(address: addr, label: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final currentAddr = wc.tronAddress?.trim() ?? '';
    final currentName = wc.activeWallet?.name ?? '当前钱包';

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _SheetUi.sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                SizedBox(
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Text(
                        '选择收款地址',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 22),
                          color: _SheetUi.labelGrey,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _optionCurrentWallet(
                  selected: _source == _AddressSource.currentWallet,
                  name: currentName,
                  address: currentAddr,
                  onTap: () => setState(
                    () => _source = _AddressSource.currentWallet,
                  ),
                ),
                const SizedBox(height: 12),
                _optionOtherWallet(
                  selected: _source == _AddressSource.otherWallet,
                  onSelect: () => setState(
                    () => _source = _AddressSource.otherWallet,
                  ),
                  onAddressBook: _openAddressBook,
                  onScan: _scanQr,
                  controller: _otherController,
                  onPaste: _pasteOther,
                  onChanged: (v) => setState(() {
                    final t = v.trim();
                    _otherLabel = t.isEmpty ? '' : _shortAddr(t);
                  }),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _footerButton(
                        label: '取消',
                        filled: false,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _footerButton(
                        label: '确认',
                        filled: true,
                        onTap: _confirm,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionCurrentWallet({
    required bool selected,
    required String name,
    required String address,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _radioIcon(selected),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '使用当前钱包',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: name,
                            style: const TextStyle(
                              color: _SheetUi.green,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: ' ${_shortAddr(address)}',
                            style: const TextStyle(
                              color: _SheetUi.labelGrey,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionOtherWallet({
    required bool selected,
    required VoidCallback onSelect,
    required VoidCallback onAddressBook,
    required VoidCallback onScan,
    required TextEditingController controller,
    required VoidCallback onPaste,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                _radioIcon(selected),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '使用其他钱包',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (selected) ...[
                  IconButton(
                    onPressed: onAddressBook,
                    icon: const Icon(
                      Icons.perm_contact_calendar_outlined,
                      size: 22,
                      color: _SheetUi.labelGrey,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                  IconButton(
                    onPressed: onScan,
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      size: 22,
                      color: _SheetUi.labelGrey,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _SheetUi.fieldBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _SheetUi.purple, width: 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      hintText: '输入账户ID',
                      hintStyle: TextStyle(color: _SheetUi.labelGrey),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onPaste,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      '粘贴',
                      style: TextStyle(
                        color: _SheetUi.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _radioIcon(bool selected) {
    return Icon(
      selected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
      color: selected ? _SheetUi.purple : const Color(0xFF48484A),
      size: 22,
    );
  }

  Widget _footerButton({
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: filled
              ? const LinearGradient(
                  colors: [_SheetUi.purple, _SheetUi.purpleEnd],
                )
              : null,
          color: filled ? null : Colors.transparent,
          border: filled
              ? null
              : Border.all(color: const Color(0xFF3A3A3E), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

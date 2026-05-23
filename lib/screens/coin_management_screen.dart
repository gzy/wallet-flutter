import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/coin_data.dart';
import '../providers/wallet_controller.dart';
import '../theme/app_colors.dart';
import '../widgets/coin_icon.dart';

/// 币种管理：显隐开关、置顶、拖拽排序（不含新增币种）。
class CoinManagementScreen extends StatefulWidget {
  const CoinManagementScreen({super.key});

  @override
  State<CoinManagementScreen> createState() => _CoinManagementScreenState();
}

class _CoinManagementScreenState extends State<CoinManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CoinData> _filtered(List<CoinData> coins) {
    if (_query.isEmpty) {
      return coins;
    }
    return coins
        .where((c) =>
            c.symbol.toLowerCase().contains(_query) ||
            c.name.toLowerCase().contains(_query) ||
            (c.network?.toLowerCase().contains(_query) == true) ||
            c.id.toLowerCase().contains(_query))
        .toList();
  }

  String _titleLine(CoinData coin) {
    final sym = coin.symbol;
    final net = coin.network?.trim();
    if (net != null && net.isNotEmpty) {
      return '$sym ($net)';
    }
    return sym;
  }

  @override
  Widget build(BuildContext context) {
    final wc = context.watch<WalletController>();
    final all = wc.allEvmCoins;
    final canReorder = _query.isEmpty;
    final list = canReorder ? all : _filtered(all);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const Text(
          '币种管理',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search,
                      color: AppColors.textMuted, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        hintText: '输入 token 名称或合约地址',
                        hintStyle: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      all.isEmpty ? '暂无币种' : '无匹配结果',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : canReorder
                    ? ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        buildDefaultDragHandles: false,
                        itemCount: list.length,
                        onReorder: (oldIndex, newIndex) {
                          context
                              .read<WalletController>()
                              .reorderManagedCoins(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final coin = list[index];
                          return _CoinManageTile(
                            key: ValueKey(
                                coin.id.isEmpty ? 'coin_$index' : coin.id),
                            index: index,
                            coin: coin,
                            titleLine: _titleLine(coin),
                            visible: wc.isCoinVisible(coin.id),
                            showDragHandle: true,
                            onPinTop: coin.id.isEmpty
                                ? null
                                : () => context
                                    .read<WalletController>()
                                    .moveCoinToTop(coin.id),
                            onVisibilityChanged: coin.id.isEmpty
                                ? null
                                : (v) => context
                                    .read<WalletController>()
                                    .setCoinVisible(coin.id, v),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final coin = list[index];
                          return _CoinManageTile(
                            key: ValueKey(
                                coin.id.isEmpty ? 'coin_$index' : coin.id),
                            index: index,
                            coin: coin,
                            titleLine: _titleLine(coin),
                            visible: wc.isCoinVisible(coin.id),
                            showDragHandle: false,
                            onPinTop: coin.id.isEmpty
                                ? null
                                : () => context
                                    .read<WalletController>()
                                    .moveCoinToTop(coin.id),
                            onVisibilityChanged: coin.id.isEmpty
                                ? null
                                : (v) => context
                                    .read<WalletController>()
                                    .setCoinVisible(coin.id, v),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CoinManageTile extends StatelessWidget {
  const _CoinManageTile({
    super.key,
    required this.index,
    required this.coin,
    required this.titleLine,
    required this.visible,
    required this.showDragHandle,
    this.onPinTop,
    this.onVisibilityChanged,
  });

  final int index;
  final CoinData coin;
  final String titleLine;
  final bool visible;
  final bool showDragHandle;
  final VoidCallback? onPinTop;
  final ValueChanged<bool>? onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CoinIcon(symbol: coin.symbol, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleLine,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  coin.name,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onPinTop != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: onPinTop,
              icon: const Icon(
                Icons.arrow_upward,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          if (showDragHandle)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.drag_handle,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
              ),
            )
          else
            const SizedBox(width: 30),
          if (onVisibilityChanged != null)
            Switch.adaptive(
              value: visible,
              activeTrackColor: AppColors.accent.withValues(alpha: 0.45),
              activeThumbColor: AppColors.accent,
              onChanged: onVisibilityChanged,
            ),
        ],
      ),
    );
  }
}

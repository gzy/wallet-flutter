import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/app_chain_config.dart';
import '../../../providers/wallet_controller.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/chain_icon.dart';

String _networkPillLabel(WalletController wc) {
  final q = wc.sendChain;
  if (q == null) {
    return '全部';
  }
  for (final c in wc.backendChains) {
    if (c.walletApiChainQuery == q) {
      final name = c.chainName.trim();
      return name.isEmpty ? q : name;
    }
  }
  return q;
}

// 兼容：历史版本里网络选择弹窗使用过 `_chainAccentColor/_chainAvatarMark`。
// 热重载时旧闭包可能仍在调用它们；保留空实现避免 NoSuchMethodError。
Color _chainAccentColor(int chainId) {
  const colors = <Color>[
    Color(0xFF3B82F6),
    Color(0xFF60A5FA),
    Color(0xFF22D3AA),
    Color(0xFFF59E0B),
    Color(0xFFA78BFA),
  ];
  return colors[chainId.abs() % colors.length];
}

String _chainAvatarMark(int chainId) {
  const marks = <String>['◆', '◉', '⬡', '◇', '◈'];
  return marks[chainId.abs() % marks.length];
}

/// 样式对齐 [TransferScreen] 内「选择币种」底部弹层（圆角、深色底、标题行、列表卡片）。
Future<String?> showWalletNetworkPicker(BuildContext context) {
  final wc = context.read<WalletController>();
  final current = wc.sendChain;
  final options = <AppChainConfig>[];
  for (final c in wc.backendChains) {
    if (c.chainId.isEmpty) {
      continue;
    }
    if (c.status != null && c.status != 1) {
      continue;
    }
    options.add(c);
  }

  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.55,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF181A21),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Row(
                  children: [
                    const Spacer(),
                    const Text(
                      '选择网络',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(
                        Icons.close,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemCount: options.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final selected = current == null;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => Navigator.pop(ctx, null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2D35),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.accent
                                      : Colors.transparent,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 21,
                                    backgroundColor: Color(0xFF3A3D45),
                                    child: Icon(
                                      Icons.grid_view_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      '全部',
                                      style: TextStyle(
                                        fontSize: 17,
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: AppColors.accent,
                                      size: 22,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    final cfg = options[index - 1];
                    final code =
                        (cfg.chainCode ?? cfg.walletApiChainQuery).trim();
                    final selected = cfg.walletApiChainQuery == current;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () =>
                              Navigator.pop(ctx, cfg.walletApiChainQuery),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2D35),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.accent
                                    : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                ChainIcon(chainCode: code, size: 42),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        cfg.chainName,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        cfg.chainType.toUpperCase() == 'EVM'
                                            ? 'EVM · Chain ${cfg.chainId}'
                                            : '${cfg.chainType} · ${cfg.walletApiChainQuery}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppColors.accent,
                                    size: 22,
                                  ),
                              ],
                            ),
                          ),
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
}

class WalletSearchBar extends StatelessWidget {
  final TextEditingController controller;

  const WalletSearchBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
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
                      controller: controller,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        hintText: '搜索',
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
          const SizedBox(width: 12),
          Consumer<WalletController>(
            builder: (context, wc, _) {
              final label = _networkPillLabel(wc);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final picked = await showWalletNetworkPicker(context);
                    if (!context.mounted) {
                      return;
                    }
                    // picked==null 表示选择了「全部」
                    context.read<WalletController>().setSendChain(picked);
                  },
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 132),
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          Container(
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.more_vert,
              color: AppColors.textSecondary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

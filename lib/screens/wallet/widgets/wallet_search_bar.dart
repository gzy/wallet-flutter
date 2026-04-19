import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/evm_environment.dart';
import '../../../models/evm_network.dart';
import '../../../providers/wallet_controller.dart';
import '../../../theme/app_colors.dart';

String _networkPillLabel(EvmNetworkId id) {
  for (final c in EvmEnvironment.nativeCoins) {
    if (c.networkKey == id) {
      return c.networkLabel;
    }
  }
  return id.shortLabel;
}

Color _networkAvatarColor(EvmNetworkId id) {
  return switch (id) {
    EvmNetworkId.ethereum => const Color(0xFF3B82F6),
    EvmNetworkId.base => const Color(0xFF60A5FA),
  };
}

String _networkAvatarMark(EvmNetworkId id) {
  return switch (id) {
    EvmNetworkId.ethereum => '◆',
    EvmNetworkId.base => '◉',
  };
}

/// 样式对齐 [TransferScreen] 内「选择币种」底部弹层（圆角、深色底、标题行、列表卡片）。
Future<EvmNetworkId?> showWalletNetworkPicker(BuildContext context) {
  final wc = context.read<WalletController>();
  final current = wc.sendNetwork;
  final options = <EvmNetworkId>[];
  for (final c in EvmEnvironment.nativeCoins) {
    if (!options.contains(c.networkKey)) {
      options.add(c.networkKey);
    }
  }

  return showModalBottomSheet<EvmNetworkId>(
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
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final id = options[index];
                    final cfg = EvmEnvironment.nativeCoins
                        .firstWhere((c) => c.networkKey == id);
                    final selected = id == current;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(ctx, id),
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
                                CircleAvatar(
                                  radius: 21,
                                  backgroundColor: _networkAvatarColor(id),
                                  child: Text(
                                    _networkAvatarMark(id),
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
                                        cfg.networkLabel,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'EVM · Chain ${id.chainId}',
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
                  const Icon(Icons.search, color: AppColors.textMuted, size: 20),
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
              final label = _networkPillLabel(wc.sendNetwork);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final picked = await showWalletNetworkPicker(context);
                    if (!context.mounted || picked == null) {
                      return;
                    }
                    context.read<WalletController>().setSendNetwork(picked);
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

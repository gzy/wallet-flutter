import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/wallet_controller.dart';
import '../../theme/app_colors.dart';

class MnemonicVerifyScreen extends StatefulWidget {
  const MnemonicVerifyScreen({super.key});

  @override
  State<MnemonicVerifyScreen> createState() => _MnemonicVerifyScreenState();
}

class _MnemonicVerifyScreenState extends State<MnemonicVerifyScreen> {
  List<String> _correctOrder = [];
  List<String> _shuffled = [];
  final List<String> _selected = [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final s = await context.read<WalletController>().readMnemonicForBackup();
      if (s == null || s.trim().isEmpty) {
        throw StateError('未找到助记词');
      }
      final words = s.trim().split(RegExp(r'\s+'));
      final rng = Random.secure();
      final shuffled = List<String>.from(words)..shuffle(rng);
      setState(() {
        _correctOrder = words;
        _shuffled = shuffled;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  void _tapWord(String w) {
    if (_selected.contains(w)) return;
    if (_selected.length >= _correctOrder.length) return;
    setState(() => _selected.add(w));
  }

  void _clear() => setState(() => _selected.clear());

  Future<void> _verify() async {
    if (_selected.length != _correctOrder.length) return;
    final ok = List.generate(_correctOrder.length, (i) => _selected[i] == _correctOrder[i]).every((e) => e);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('助记词顺序不正确，请重试')));
      _clear();
      return;
    }
    await context.read<WalletController>().markBackedUp();
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(backgroundColor: AppColors.background, title: const Text('备份')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!, style: const TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }

    final complete = _selected.length == _correctOrder.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        '备份',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(26, 10, 26, 0),
              child: Text(
                '请按顺序点击助记词，以验证你备份的助记词正确。',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _correctOrder.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.25,
                ),
                itemBuilder: (context, i) {
                  final word = i < _selected.length ? _selected[i] : null;
                  final filled = word != null;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: filled ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: filled ? null : Border.all(color: AppColors.borderSoft),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${i + 1}',
                          style: TextStyle(color: filled ? const Color(0xFFA1A1AA) : AppColors.textMuted, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            filled ? word : 'word',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: filled ? Colors.black : Colors.transparent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _selected.isEmpty ? null : _clear,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('清空', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _shuffled.map((w) {
                    final selected = _selected.contains(w);
                    return SizedBox(
                      height: 42,
                      child: FilledButton(
                        onPressed: selected ? null : () => _tapWord(w),
                        style: FilledButton.styleFrom(
                          backgroundColor: selected ? AppColors.surface : Colors.white,
                          foregroundColor: selected ? AppColors.textMuted : Colors.black,
                          disabledBackgroundColor: AppColors.surface,
                          disabledForegroundColor: AppColors.textMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(w, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: complete ? _verify : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.accentText,
                    disabledBackgroundColor: AppColors.surfaceElevated,
                    disabledForegroundColor: AppColors.textMuted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('验证', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

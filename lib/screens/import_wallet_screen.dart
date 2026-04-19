import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/wallet_controller.dart';
import '../services/wallet/local_backup_service.dart';
import '../services/wallet/mnemonic_service.dart';
import '../theme/app_colors.dart';
import '../widgets/security_pin_bottom_sheet.dart';
import 'wallet_ready_screen.dart';

/// 导入钱包：双端统一交互
/// - Tab1：粘贴助记词
/// - Tab2：选择本应用导出的 `.json` 备份文件 + 备份密码解密（与 iOS/Android 系统文件选择器集成）
class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _text = TextEditingController();
  final TextEditingController _backupPwd = TextEditingController();
  bool _showBackupPwd = false;

  String? _pickedName;
  Uint8List? _fileBytes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _text.dispose();
    _backupPwd.dispose();
    super.dispose();
  }

  Future<void> _openPinSheetWithPhrase(String phrase) async {
    final setupMode = !context.read<WalletController>().pinEnabled;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (sheetContext) => SecurityPinBottomSheet(
        setupMode: setupMode,
        onSubmit: (pin) async {
          final nav = Navigator.of(sheetContext);
          try {
            await context.read<WalletController>().importWallet(phrase, pin);
            if (!mounted) return;
            nav.pop();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletReadyScreen()),
            );
          } catch (e) {
            if (mounted) {
              final msg = e is StateError ? e.message : '导入失败: $e';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg)),
              );
            }
            rethrow;
          }
        },
      ),
    );
  }


  Future<void> _submitMnemonicTab() async {
    final raw = _text.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入助记词')),
      );
      return;
    }
    final phrase = raw.replaceAll(RegExp(r'\s+'), ' ');
    if (!MnemonicService.validateMnemonic(phrase)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('助记词无效，请检查单词与空格')),
      );
      return;
    }
    final dup = await context.read<WalletController>().findWalletWithSameMnemonic(phrase);
    if (!mounted) return;
    if (dup != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('该助记词已在钱包「${dup.name}」中使用，无需重复导入')),
      );
      return;
    }
    await _openPinSheetWithPhrase(phrase);
  }

  /// iOS / Android 均走系统文档选择器；`withData: true` 将文件读入内存，避免部分机型路径权限问题。
  Future<void> _pickBackupFile() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) {
      return;
    }
    final f = r.files.single;
    final bytes = f.bytes;
    setState(() {
      _pickedName = f.name;
      _fileBytes = bytes;
    });
    if (bytes == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该文件，请重试或换用文件选择器')),
      );
    }
  }

  Future<void> _decryptBackupAndOpenPin() async {
    final bytes = _fileBytes;
    if (bytes == null || bytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择备份文件（.json）')),
      );
      return;
    }
    final pwd = _backupPwd.text;
    if (pwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入备份密码')),
      );
      return;
    }
    try {
      final json = utf8.decode(bytes);
      final phrase = LocalBackupService.decryptLocalBackup(json, pwd);
      if (!mounted) return;
      final normalized = phrase.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (!MnemonicService.validateMnemonic(normalized)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份中的助记词无效')),
        );
        return;
      }
      final dup = await context.read<WalletController>().findWalletWithSameMnemonic(normalized);
      if (!mounted) return;
      if (dup != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('该助记词已在钱包「${dup.name}」中使用，无需重复导入')),
        );
        return;
      }
      await _openPinSheetWithPhrase(normalized);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解密失败，请检查密码与文件：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('导入钱包'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppColors.border,
          dividerHeight: 1,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          tabs: const [
            Tab(text: '助记词'),
            Tab(text: '备份文件'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMnemonicTab(),
          _buildBackupFileTab(),
        ],
      ),
    );
  }

  Widget _buildMnemonicTab() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '使用空格分隔单词，按 BIP-39 标准输入 12 或 24 个英文单词。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15, height: 1.35),
                decoration: InputDecoration(
                  hintText: 'word1 word2 word3 ...',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _submitMnemonicTab,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentText,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('下一步',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupFileTab() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '选择本应用「备份」流程生成的加密 JSON 文件，并输入当时设置的备份密码。解密成功后，将引导设置或验证 6 位安全密码以完成导入。',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickBackupFile,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.borderSoft),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(
                  _pickedName == null ? '选择备份文件 (.json)' : '已选择: $_pickedName'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _backupPwd,
              obscureText: !_showBackupPwd,
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                labelText: '备份密码',
                labelStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showBackupPwd = !_showBackupPwd),
                  icon: Icon(
                    _showBackupPwd ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textSecondary,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _decryptBackupAndOpenPin,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentText,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('解密并继续',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

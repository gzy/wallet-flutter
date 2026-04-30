import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'data/local/app_local_cache.dart';
import 'theme/app_colors.dart';
import 'providers/wallet_controller.dart';
import 'services/install/install_guard.dart';
import 'screens/wallet_screen.dart';
import 'screens/market_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/flash_screen.dart';
import 'screens/trade_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/welcome_screen.dart';

// 临时预览欢迎页：改为 false 即恢复正常（有钱包进主页、PIN 照常）。
const bool _previewWelcome = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarDividerColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  try {
    await InstallGuard.purgeWalletSecretsOnFreshInstall();
  } catch (_) {
    // 首次安装检测失败时，为避免阻塞启动，继续运行。
  }
  AppLocalCache? appCache;
  if (!kIsWeb) {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
      }
      appCache = AppLocalCache.open();
    } catch (e, st) {
      debugPrint('AppLocalCache init failed: $e\n$st');
    }
  }
  runApp(
    ChangeNotifierProvider<WalletController>(
      create: (_) {
        final c = WalletController(localCache: appCache);
        c.init();
        return c;
      },
      child: const WalletApp(),
    ),
  );
}

class WalletApp extends StatelessWidget {
  const WalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.background,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
      // 解锁层盖在整个 Navigator 之上，否则从首页 push 的详情页会挡住 _HomeShell 里的 UnlockScreen。
      // 无钱包时不叠 PIN：否则欢迎页被挡住；且尚未有可保护资产时不必先解锁。
      builder: (context, child) {
        return Consumer<WalletController>(
          builder: (context, w, _) {
            if (child == null) return const SizedBox.shrink();
            // 切后台时不展示 UnlockScreen（避免 App 切换器里出现 PIN），也不盖黑色遮罩（保持正常页面快照）。
            if (w.appInBackground) {
              return child;
            }
            final needUnlock = w.initReady &&
                w.hasWallet &&
                w.pinEnabled &&
                !w.sessionUnlocked &&
                !_previewWelcome;
            if (needUnlock) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  const Positioned.fill(child: UnlockScreen()),
                ],
              );
            }
            return child;
          },
        );
      },
      home: const _HomeShell(),
    );
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> with WidgetsBindingObserver {
  static const Duration _startupWelcomeDuration = Duration(seconds: 2);
  Timer? _startupWelcomeTimer;
  bool _forceShowWelcome = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _startupWelcomeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进入后台/不可见即上锁；回到前台按 30 分钟窗口决定是否免 PIN
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      context.read<WalletController>().onAppBackgrounded();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      context.read<WalletController>().onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WalletController>(
      builder: (context, w, _) {
        if (!w.initReady) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        if (_previewWelcome) {
          return const WelcomeScreen();
        }
        // 每次冷启动先展示欢迎页 2s；无钱包则一直停留，并展示底部按钮。
        if (!w.hasWallet) {
          _startupWelcomeTimer?.cancel();
          _forceShowWelcome = true;
          return const WelcomeScreen(allowActions: true);
        }
        if (_forceShowWelcome) {
          _startupWelcomeTimer ??= Timer(_startupWelcomeDuration, () {
            if (!mounted) return;
            setState(() => _forceShowWelcome = false);
          });
          return const WelcomeScreen(allowActions: false);
        }
        // PIN 未解锁时不挂载 MainTabs（IndexedStack 会同时保持 5 个 Tab 存活并重绘），解锁层由上层 Stack 提供。
        if (w.pinEnabled && !w.sessionUnlocked) {
          return const ColoredBox(
            color: AppColors.background,
            child: SizedBox.expand(),
          );
        }
        return const MainTabs();
      },
    );
  }
}

class MainTabs extends StatefulWidget {
  const MainTabs({super.key});

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _currentIndex = 0;

  static const List<_TabItem> _tabs = [
    _TabItem(
        title: '钱包',
        icon: Icons.account_balance_wallet_outlined,
        page: WalletScreen()),
    _TabItem(title: '市场', icon: Icons.bar_chart_outlined, page: MarketScreen()),
    _TabItem(title: '探索', icon: Icons.grid_view_rounded, page: ExploreScreen()),
    _TabItem(title: '闪兑', icon: Icons.repeat_rounded, page: FlashScreen()),
    _TabItem(
        title: '交易', icon: Icons.compare_arrows_rounded, page: TradeScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs.map((e) => e.page).toList(),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: AppColors.accent,
            unselectedItemColor: AppColors.textMuted,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
            items: _tabs
                .map((e) => BottomNavigationBarItem(
                      icon: Icon(e.icon, size: 24),
                      label: e.title,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String title;
  final IconData icon;
  final Widget page;
  const _TabItem({required this.title, required this.icon, required this.page});
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wallet_flutter/main.dart';
import 'package:wallet_flutter/providers/wallet_controller.dart';

void main() {
  testWidgets('App launches and shows welcome screen',
      (WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    // Minimal in-memory mock for flutter_secure_storage in widget tests.
    final mem = <String, String?>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (call) async {
        switch (call.method) {
          case 'read':
            final key = (call.arguments as Map?)?['key']?.toString();
            return key == null ? null : mem[key];
          case 'write':
            final args = (call.arguments as Map?) ?? const {};
            final key = args['key']?.toString();
            if (key == null) return null;
            mem[key] = args['value']?.toString();
            return null;
          case 'delete':
            final key = (call.arguments as Map?)?['key']?.toString();
            if (key != null) mem.remove(key);
            return null;
          case 'readAll':
            return Map<String, String?>.from(mem);
          case 'deleteAll':
            mem.clear();
            return null;
          default:
            return null;
        }
      },
    );

    late WalletController controller;
    await tester.pumpWidget(
      ChangeNotifierProvider<WalletController>(
        create: (_) {
          controller = WalletController();
          return controller;
        },
        child: const WalletApp(),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => controller.init());
    await tester.pumpAndSettle();

    // Default state (no wallet yet) should show WelcomeScreen CTA.
    // WelcomeScreen delays CTA reveal by 2s.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Create Wallet'), findsOneWidget);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });
}

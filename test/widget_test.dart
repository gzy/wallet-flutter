import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:wallet_flutter/main.dart';
import 'package:wallet_flutter/providers/wallet_controller.dart';

void main() {
  testWidgets('App launches and shows wallet tab', (WidgetTester tester) async {
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

    expect(find.text('钱包'), findsOneWidget);
  });
}

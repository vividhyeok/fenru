import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fenru/main.dart' as app;
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app launches and presents a workspace or onboarding', (tester) async {
    await app.main([]);
    await tester.pumpAndSettle();
    expect(find.text('Fenru'), findsWidgets);
  });
}

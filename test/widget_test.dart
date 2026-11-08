import 'package:flutter_test/flutter_test.dart';
import 'package:neu_better_pro/app/app.dart';

void main() {
  testWidgets('M0 shell renders the project status', (tester) async {
    await tester.pumpWidget(const NeuBetterApp());

    expect(find.text('NEU Better'), findsOneWidget);
    expect(find.text('工程底座已就绪'), findsOneWidget);
    expect(find.text('M1 · 登录与持久会话'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neu_better_pro/app/widgets/shared_axis_switcher.dart';

void main() {
  Future<void> pumpSwitcher(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: SharedAxisSwitcher(
                forward: true,
                duration: const Duration(milliseconds: 100),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('同一 key 的内容更新立即生效（不播放转场）', (tester) async {
    await pumpSwitcher(
      tester,
      const KeyedSubtree(key: ValueKey('list'), child: Text('A')),
    );
    expect(find.text('A'), findsOneWidget);

    await pumpSwitcher(
      tester,
      const KeyedSubtree(key: ValueKey('list'), child: Text('B')),
    );
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('不同 key 播放转场并最终只显示新内容', (tester) async {
    await pumpSwitcher(
      tester,
      const KeyedSubtree(key: ValueKey('list'), child: Text('A')),
    );

    await pumpSwitcher(
      tester,
      const KeyedSubtree(key: ValueKey('detail-1'), child: Text('C')),
    );
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });
}

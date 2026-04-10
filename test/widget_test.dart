import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secret_book/pages/unlock_page.dart';

void main() {
  testWidgets('unlock page renders primary controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnlockPage(
          username: 'alice',
          onUnlock: (_) async {},
          onChangeUser: () {},
        ),
      ),
    );

    expect(find.text('解锁 Secret Book'), findsOneWidget);
    expect(find.text('主密码'), findsOneWidget);
    expect(find.text('解锁'), findsOneWidget);
    expect(find.text('当前用户：alice'), findsOneWidget);
  });
}
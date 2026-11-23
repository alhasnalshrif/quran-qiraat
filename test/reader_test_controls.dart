import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapReaderToToggleControls(WidgetTester tester) async {
  await tester.tap(find.byType(PageView));
  await tester.pumpAndSettle();
}

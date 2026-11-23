import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/about/about_page.dart';

/// Q-05: the About page lists every source with its licence, and the ones the
/// project reviewed and rejected, so nothing ships unattributed.
void main() {
  Future<void> pump(WidgetTester tester) async {
    // A tall surface so the whole ListView builds in one pass; ListView is lazy
    // and would otherwise not instantiate rows below the fold.
    tester.view.physicalSize = const Size(440, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: AboutPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows every source with a licence (Q-05)', (tester) async {
    await pump(tester);

    // Every declared source appears by name.
    for (final source in AboutPage.sources) {
      expect(
        find.text(source.name),
        findsOneWidget,
        reason: 'missing source ${source.name}',
      );
    }

    // Licences are rendered, not just stored.
    for (final licence in {'ISC', 'MIT', 'OFL 1.1', 'شروط المجمع'}) {
      expect(
        find.textContaining(licence, findRichText: true),
        findsWidgets,
        reason: 'missing licence $licence',
      );
    }
  });

  testWidgets('says what was rejected and why (Q-05)', (tester) async {
    await pump(tester);
    expect(find.text('ما رُفض ولماذا'), findsOneWidget);
    for (final reason in AboutPage.rejected) {
      expect(find.textContaining(reason.substring(0, 12)), findsWidgets);
    }
  });

  testWidgets('states the privacy position (Q-05)', (tester) async {
    await pump(tester);
    expect(find.textContaining('لا حسابات ولا تتبع'), findsOneWidget);
  });

  test('every path the page credits exists in the repository (Q-05)', () {
    // Guards against the About page drifting from what actually ships.
    for (final source in AboutPage.sources) {
      final paths = source.path.split('·').map((part) => part.trim());
      for (final path in paths) {
        expect(
          FileSystemEntity.typeSync(path),
          isNot(FileSystemEntityType.notFound),
          reason: '${source.name} credits a missing path: $path',
        );
      }
    }
  });

  test('every source carries a non-empty licence and path', () {
    for (final source in AboutPage.sources) {
      expect(source.licence.trim(), isNotEmpty, reason: source.name);
      expect(source.path.trim(), isNotEmpty, reason: source.name);
      expect(source.origin.trim(), isNotEmpty, reason: source.name);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/updates/update_sheets.dart';
import 'package:quran_qiraat/updates/protocol.dart';

/// A-08: the four sheets' priority and dismissal rules (03 §6, D19).
void main() {
  final policy = AppPolicy(
    latestBuild: 9,
    minSupportedBuild: 5,
    storeUrl: Uri.parse('https://apps.apple.com/app/id1'),
    message: const LocalizedText(ar: 'رسالة التحديث'),
  );

  final pack = PackRelease(
    packId: 'qiraat-farsh',
    version: 2,
    format: 'qiraat-variants@1',
    notes: const LocalizedText(ar: 'تصحيح مواضع الفرش'),
    files: [
      PackFile(
        path: 'variants.json',
        url: Uri.parse('https://cdn.example.com/v.json'),
        sha256: '9f2c5b8e1a7d4f0c3b6e9a2d5f8c1b4e7a0d3f6c9b2e5a8d1f4c7b0e3a6d9f2c',
        size: 10,
      ),
    ],
  );

  final announcement = Announcement(
    id: 'a-1',
    title: const LocalizedText(ar: 'إعلان'),
    body: const LocalizedText(ar: 'نص الإعلان'),
    startsAt: DateTime.utc(2026, 11, 1),
    endsAt: DateTime.utc(2026, 12, 1),
    priority: 'normal',
  );

  Future<void> pumpHost(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: Builder(builder: (context) => child)),
    ),
  );

  group('priority queue (A-08)', () {
    test('forced update wins over everything', () {
      final queue = UpdateSheetQueue(
        requiresUpdate: true,
        hasOptionalUpdate: true,
      );
      expect(
        queue.next(pending: [pack], announcements: [announcement]),
        UpdateSheet.forcedUpdate,
      );
    });

    test('ready data comes before optional update and announcements', () {
      final queue = UpdateSheetQueue(
        requiresUpdate: false,
        hasOptionalUpdate: true,
      );
      expect(
        queue.next(pending: [pack], announcements: [announcement]),
        UpdateSheet.dataReady,
      );
    });

    test('optional update comes before an announcement', () {
      final queue = UpdateSheetQueue(
        requiresUpdate: false,
        hasOptionalUpdate: true,
      );
      expect(
        queue.next(pending: const [], announcements: [announcement]),
        UpdateSheet.optionalUpdate,
      );
    });

    test('announcement is last, and nothing else means no sheet', () {
      final queue = UpdateSheetQueue(
        requiresUpdate: false,
        hasOptionalUpdate: false,
      );
      expect(
        queue.next(pending: const [], announcements: [announcement]),
        UpdateSheet.announcement,
      );
      expect(
        queue.next(pending: const [], announcements: const []),
        isNull,
      );
    });

    test('never shows a second sheet while one is open', () {
      final queue = UpdateSheetQueue(
        requiresUpdate: true,
        hasOptionalUpdate: true,
      );
      expect(queue.next(pending: const [], announcements: const []),
          UpdateSheet.forcedUpdate);
      queue.begin();
      expect(
        queue.next(pending: [pack], announcements: [announcement]),
        isNull,
      );
      queue.end();
      expect(
        queue.next(pending: const [], announcements: const []),
        UpdateSheet.forcedUpdate,
      );
    });
  });

  group('sheets render (A-08)', () {
    testWidgets('forced update shows its title and store button', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateSheet(
              context: context,
              sheet: UpdateSheet.forcedUpdate,
              policy: policy,
              onOpenStore: () {},
              onApplyNow: () {},
              onDismissOptional: () {},
              onDismissDataReady: () {},
              onDismissAnnouncement: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);
      expect(find.text('رسالة التحديث'), findsOneWidget);
      expect(find.text('فتح المتجر'), findsOneWidget);
    });

    testWidgets('forced update cannot be dismissed by dragging down', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateSheet(
              context: context,
              sheet: UpdateSheet.forcedUpdate,
              policy: policy,
              onOpenStore: () {},
              onApplyNow: () {},
              onDismissOptional: () {},
              onDismissDataReady: () {},
              onDismissAnnouncement: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Drag the sheet far down; a dismissible sheet would have closed.
      await tester.drag(find.text('يلزم تحديث التطبيق'), const Offset(0, 600));
      await tester.pumpAndSettle();

      expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);
    });

    testWidgets('data ready lists packs and applies now', (tester) async {
      var applied = false;
      await pumpHost(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateSheet(
              context: context,
              sheet: UpdateSheet.dataReady,
              pendingPacks: [pack],
              onOpenStore: () {},
              onApplyNow: () => applied = true,
              onDismissOptional: () {},
              onDismissDataReady: () {},
              onDismissAnnouncement: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('تحديث بيانات جاهز'), findsOneWidget);
      expect(find.text('تصحيح مواضع الفرش'), findsOneWidget);

      await tester.tap(find.text('تطبيق الآن'));
      await tester.pumpAndSettle();
      expect(applied, isTrue);
      expect(find.text('تحديث بيانات جاهز'), findsNothing);
    });

    testWidgets('forced update survives the Android back button', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateSheet(
              context: context,
              sheet: UpdateSheet.forcedUpdate,
              policy: policy,
              onOpenStore: () {},
              onApplyNow: () {},
              onDismissOptional: () {},
              onDismissDataReady: () {},
              onDismissAnnouncement: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('يلزم تحديث التطبيق'), findsOneWidget);
    });

    testWidgets('optional update can be dismissed and records the dismissal',
        (tester) async {
      var dismissed = false;
      await pumpHost(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateSheet(
              context: context,
              sheet: UpdateSheet.optionalUpdate,
              policy: policy,
              onOpenStore: () {},
              onApplyNow: () {},
              onDismissOptional: () => dismissed = true,
              onDismissDataReady: () {},
              onDismissAnnouncement: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('نسخة جديدة'), findsOneWidget);
      await tester.tap(find.text('لاحقًا'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
      expect(find.text('نسخة جديدة'), findsNothing);
    });

    testWidgets('announcement shows its title and body', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateSheet(
              context: context,
              sheet: UpdateSheet.announcement,
              announcement: announcement,
              onOpenStore: () {},
              onApplyNow: () {},
              onDismissOptional: () {},
              onDismissDataReady: () {},
              onDismissAnnouncement: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('إعلان'), findsOneWidget);
      expect(find.text('نص الإعلان'), findsOneWidget);
      // No url means no open button.
      expect(find.text('فتح'), findsNothing);
      expect(find.text('إغلاق'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennywise/app.dart';
import 'package:pennywise/repositories/in_memory_finance_repository.dart';
import 'package:pennywise/services/demo_data.dart';
import 'package:pennywise/services/update_service.dart';
import 'package:pennywise/shell/penny_bottom_bar.dart';
import 'package:pennywise/state/finance_store.dart';
import 'package:pennywise/state/update_controller.dart';

Future<FinanceStore> _store({bool demo = false}) async {
  final store = FinanceStore(InMemoryFinanceRepository(),
      clock: () => DateTime(2026, 11, 6, 12));
  await store.load();
  if (demo) {
    await store.insertMany(DemoData.generate(store.categories, now: store.now));
  }
  return store;
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
}

Finder _nav(String label) => find.descendant(
    of: find.byType(PennyBottomBar), matching: find.text(label));

Future<void> _flushSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state dashboard renders', (tester) async {
    _phoneSize(tester);
    final store = await _store();
    await tester.pumpWidget(PennyWiseApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Total balance'), findsOneWidget);
    expect(find.text('Welcome to PennyWise'), findsOneWidget);
    expect(find.text('Explore with demo data'), findsOneWidget);
  });

  testWidgets('dashboard with data and all tabs render', (tester) async {
    _phoneSize(tester);
    final store = await _store(demo: true);
    await tester.pumpWidget(PennyWiseApp(store: store));
    await tester.pumpAndSettle();

    expect(find.text('Smart insights'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);

    await tester.tap(_nav('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Spent'), findsWidgets);

    await tester.tap(_nav('Budget'));
    await tester.pumpAndSettle();
    expect(find.text('Set a monthly budget'), findsOneWidget);

    await tester.tap(_nav('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile & settings'), findsOneWidget);
  });

  testWidgets('smart entry fills the form and saves after confirmation',
      (tester) async {
    _phoneSize(tester);
    final store = await _store();
    await tester.pumpWidget(PennyWiseApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(PennyBottomBar),
        matching: find.byIcon(Icons.add_rounded)));
    await tester.pumpAndSettle();
    expect(find.text('Add transaction'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).first, 'I spent 250 rupees on lunch');
    await tester.tap(find.byIcon(Icons.arrow_circle_right_rounded));
    await tester.pumpAndSettle();

    // Nothing is saved until the user confirms.
    expect(store.transactions, isEmpty);
    expect(find.text('Use these details'), findsOneWidget);

    await tester.tap(find.text('Use these details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(store.transactions, hasLength(1));
    final t = store.transactions.single;
    expect(t.amountMinor, 25000);
    expect(t.note, 'Lunch');
    expect(store.categoryById(t.categoryId)?.name, 'Food & Dining');

    await _flushSnackBars(tester);
  });

  testWidgets('saving without an amount shows a validation error',
      (tester) async {
    _phoneSize(tester);
    final store = await _store();
    await tester.pumpWidget(PennyWiseApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(PennyBottomBar),
        matching: find.byIcon(Icons.add_rounded)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    expect(store.transactions, isEmpty);
  });

  testWidgets('update banner appears when a newer build is published',
      (tester) async {
    _phoneSize(tester);
    final store = await _store();
    final updates = UpdateController(
      configured: true,
      currentBuild: 3,
      fetchLatest: () async => const UpdateInfo(
        buildNumber: 5,
        title: 'PennyWise 1.0.5',
        notes: 'Faster charts',
        apkUrl: 'https://example.com/PennyWise.apk',
        pageUrl: 'https://example.com',
      ),
    );
    await tester.pumpWidget(PennyWiseApp(store: store, updates: updates));
    await updates.check(silent: true);
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(find.text('Update to version 1.0.5'), findsOneWidget);
    expect(find.text('Faster charts'), findsOneWidget);
  });

  testWidgets('create a note from the dashboard', (tester) async {
    _phoneSize(tester);
    final store = await _store();
    await tester.pumpWidget(PennyWiseApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notes & reminders'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);

    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Lent money to Ravi');
    await tester.tap(find.text('Tomorrow 9 AM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & set reminder'));
    await tester.pumpAndSettle();

    expect(store.notes, hasLength(1));
    expect(store.notes.single.title, 'Lent money to Ravi');
    expect(store.notes.single.reminderAt, isNotNull);
    expect(find.text('Lent money to Ravi'), findsOneWidget);
    await _flushSnackBars(tester);
  });
}

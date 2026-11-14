import 'package:flutter/material.dart';

import 'app.dart';
import 'database/app_database.dart';
import 'models/transaction_entry.dart';
import 'repositories/finance_repository.dart';
import 'repositories/sqlite_finance_repository.dart';
import 'screens/add_transaction/add_transaction_screen.dart';
import 'screens/notes/note_editor_screen.dart';
import 'screens/sms/sms_import_sheet.dart';
import 'services/reminder_service.dart';
import 'services/shortcut_service.dart';
import 'state/finance_store.dart';
import 'state/update_controller.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final FinanceRepository repository;
  try {
    repository = SqliteFinanceRepository(await AppDatabase.open());
  } catch (e) {
    runApp(_StartupErrorApp(error: e.toString()));
    return;
  }

  final navigatorKey = GlobalKey<NavigatorState>();
  final reminders = LocalReminderScheduler();
  final store = FinanceStore(repository, reminders: reminders);

  // Tapping a notification opens the matching screen.
  void handleTap(String payload) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (payload == ReminderPayload.addTransaction) {
      nav.push(MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => const AddTransactionScreen()));
      return;
    }
    final id = ReminderPayload.noteId(payload);
    final note = id == null ? null : store.noteById(id);
    if (note == null) return;
    nav.push(MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(existing: note)));
  }

  void handleShortcut(ShortcutAction shortcut) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    if (shortcut.isAddExpense) {
      nav.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            const AddTransactionScreen(initialType: TransactionType.expense),
      ));
    } else if (shortcut.isAddIncome) {
      nav.push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            const AddTransactionScreen(initialType: TransactionType.income),
      ));
    } else if (shortcut.isAddNote) {
      nav.push(MaterialPageRoute<void>(
        builder: (_) => const NoteEditorScreen(),
      ));
    } else if (shortcut.isProcessText && shortcut.text != null) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        SmsImportSheet.show(context, initialText: shortcut.text);
      }
    }
  }

  ShortcutService.instance.init();
  ShortcutService.instance.stream.listen(handleShortcut);

  await reminders.init(onTap: handleTap);
  await store.load();

  final updates = UpdateController();
  runApp(PennyWiseApp(
      store: store, updates: updates, navigatorKey: navigatorKey));

  final launched = await reminders.launchedPayload();
  if (launched != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => handleTap(launched));
  }
  final initialShortcut = await ShortcutService.instance.getInitialAction();
  if (initialShortcut != null) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => handleShortcut(initialShortcut));
  }
  // Quietly look for a newer version (only for GitHub-built APKs).
  if (store.settings.autoUpdateCheck) updates.check(silent: true);
}

/// Shown only if the local database cannot be opened at all.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'PennyWise could not open its local database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

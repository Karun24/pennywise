import 'package:flutter/material.dart';

import 'app.dart';
import 'database/app_database.dart';
import 'repositories/finance_repository.dart';
import 'repositories/sqlite_finance_repository.dart';
import 'screens/notes/note_editor_screen.dart';
import 'services/reminder_service.dart';
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

  // Tapping a reminder notification opens that note.
  void openNote(int id) {
    final note = store.noteById(id);
    final nav = navigatorKey.currentState;
    if (note == null || nav == null) return;
    nav.push(MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(existing: note)));
  }

  await reminders.init(onOpenNote: openNote);
  await store.load();

  final updates = UpdateController();
  runApp(PennyWiseApp(
      store: store, updates: updates, navigatorKey: navigatorKey));

  final launchedNote = await reminders.launchedFromNote();
  if (launchedNote != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => openNote(launchedNote));
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

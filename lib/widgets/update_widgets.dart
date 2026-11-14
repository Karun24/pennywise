import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/backup_file_service.dart';
import '../services/update_service.dart';
import '../state/finance_store.dart';
import '../state/update_controller.dart';
import '../theme/theme_ext.dart';
import '../utils/date_utils.dart';
import 'dialogs.dart';

/// Card shown at the top of the dashboard when a newer version exists.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateController>();
    final info = updates.available;
    if (!updates.hasUpdate || info == null) return const SizedBox.shrink();
    final accent = context.penny.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: accent.withValues(alpha: context.isDark ? 0.14 : 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accent.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => showUpdateSheet(context, info),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Update available',
                          style: context.text.titleSmall),
                      Text(
                        'Version 1.0.${info.buildNumber} is ready to install',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(72, 38),
                  ),
                  onPressed: () => showUpdateSheet(context, info),
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains the update and opens the APK download in the browser.
Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          Text('Update to version 1.0.${info.buildNumber}',
              style: ctx.text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'You have ${AppBuildInfo.versionLabel}'
            '${info.publishedAt == null ? '' : ' · released ${DateUtilsX.dayMonthYear(info.publishedAt!.toLocal())}'}',
            style: ctx.text.bodySmall,
          ),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text("What's new", style: ctx.text.titleSmall),
            const SizedBox(height: 6),
            Text(info.notes, style: ctx.text.bodyMedium),
          ],
          const SizedBox(height: 20),
          _Step(
            number: 1,
            title: 'Back up your data (recommended)',
            body: 'Saves a copy of everything, just in case.',
            action: OutlinedButton.icon(
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Export backup'),
              onPressed: () async {
                final store = ctx.read<FinanceStore>();
                final messenger = ScaffoldMessenger.of(ctx);
                try {
                  await const BackupFileService()
                      .shareBackup(ctx, store.snapshot());
                } catch (e) {
                  messenger.showSnackBar(
                      pennySnack('Could not export the backup. $e',
                          error: true));
                }
              },
            ),
          ),
          _Step(
            number: 2,
            title: 'Download the update',
            body: 'Opens your browser and downloads PennyWise.apk.',
            action: FilledButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download update'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(ctx);
                final ok = await launchUrl(Uri.parse(info.apkUrl),
                    mode: LaunchMode.externalApplication);
                if (!ok) {
                  messenger.showSnackBar(pennySnack(
                      'Could not open the browser. Link: ${info.apkUrl}',
                      error: true));
                }
              },
            ),
          ),
          const _Step(
            number: 3,
            title: 'Install it',
            body: 'Open the downloaded file and tap Update. Do not uninstall '
                'PennyWise first - installing over it keeps all your data.',
          ),
        ],
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    this.action,
  });

  final int number;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.colors.primary.withValues(alpha: 0.15),
            child: Text('$number',
                style: context.text.labelLarge
                    ?.copyWith(color: context.colors.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: context.text.bodySmall),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

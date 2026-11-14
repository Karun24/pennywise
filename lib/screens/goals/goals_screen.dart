import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/goal.dart';
import '../../state/finance_store.dart';
import '../../theme/theme_ext.dart';
import '../../utils/category_icons.dart';
import '../../utils/date_utils.dart';
import '../../utils/money.dart';
import '../../widgets/common.dart';
import '../../widgets/dialogs.dart';
import 'goal_editor_sheet.dart';

/// Full screen to track and manage savings targets.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const GoalsScreen()));

  Future<void> _addSavings(BuildContext context, Goal goal) async {
    final store = context.read<FinanceStore>();
    final currency = store.currency;
    final controller = TextEditingController();
    String? error;

    final added = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Add to "${goal.name}"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Remaining: ${Money.format(goal.remainingMinor, currency)}',
                style: ctx.text.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount to add',
                  prefixText: '${currency.symbol} ',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final amount in [500, 1000, 2000, 5000])
                    ActionChip(
                      label: Text('${currency.symbol}$amount'),
                      onPressed: () {
                        setDialog(() {
                          controller.text = '$amount';
                          error = null;
                        });
                      },
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final minor = Money.parseToMinor(controller.text);
                if (minor == null || minor <= 0) {
                  setDialog(() => error = 'Enter a valid amount');
                  return;
                }
                Navigator.of(ctx).pop(minor);
              },
              child: const Text('Add savings'),
            ),
          ],
        ),
      ),
    );

    if (added == null || !context.mounted) return;
    try {
      await store.addGoalSavings(goal, added);
      final newTotal = goal.savedMinor + added;
      if (newTotal >= goal.targetMinor) {
        if (context.mounted) {
          showSnack(context, '🎉 Goal "${goal.name}" achieved!');
        }
      } else {
        if (context.mounted) {
          showSnack(
              context, 'Added ${store.format(added)} to "${goal.name}".');
        }
      }
    } on StoreException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _delete(BuildContext context, Goal goal) async {
    final store = context.read<FinanceStore>();
    final ok = await confirmAction(
      context,
      title: 'Delete "${goal.name}"?',
      message: 'This will remove the savings goal from your list.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await store.deleteGoal(goal);
      if (context.mounted) {
        showSnack(context, 'Goal "${goal.name}" deleted.');
      }
    } on StoreException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<FinanceStore>();
    final currency = store.currency;
    final goals = store.goals;
    final activeGoals = goals.where((g) => !g.isAchieved).toList();
    final completedGoals = goals.where((g) => g.isAchieved).toList();

    var totalTarget = 0;
    for (final g in goals) {
      totalTarget += g.targetMinor;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGoalEditor(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New goal'),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: ListView(
            padding: pagePadding(context, top: 4, bottom: 96),
            children: [
              if (goals.isNotEmpty) ...[
                PennyCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.penny.income
                                  .withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.savings_rounded,
                                color: context.penny.income),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total saved towards goals',
                                    style: context.text.bodySmall),
                                const SizedBox(height: 2),
                                Text(
                                  Money.format(
                                      store.totalSavedInGoals, currency),
                                  style: context.text.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: tabularFigures,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _StatBox(
                              label: 'Active goals',
                              value: '${activeGoals.length}',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatBox(
                              label: 'Completed',
                              value: '${completedGoals.length}',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _StatBox(
                              label: 'Total target',
                              value: Money.format(totalTarget, currency),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (goals.isEmpty)
                EmptyState(
                  icon: Icons.savings_rounded,
                  title: 'No savings goals yet',
                  message:
                      'Create a goal for a vacation, emergency fund, or a new gadget to track your progress.',
                  action: FilledButton.icon(
                    onPressed: () => showGoalEditor(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create a goal'),
                  ),
                )
              else ...[
                if (activeGoals.isNotEmpty) ...[
                  Text('In Progress', style: context.text.titleMedium),
                  const SizedBox(height: 10),
                  for (final g in activeGoals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GoalCard(
                        goal: g,
                        currency: currency,
                        now: store.now,
                        onAddSavings: () => _addSavings(context, g),
                        onEdit: () => showGoalEditor(context, existing: g),
                        onDelete: () => _delete(context, g),
                      ),
                    ),
                ],
                if (completedGoals.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Completed Goals 🎉', style: context.text.titleMedium),
                  const SizedBox(height: 10),
                  for (final g in completedGoals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GoalCard(
                        goal: g,
                        currency: currency,
                        now: store.now,
                        onAddSavings: () => _addSavings(context, g),
                        onEdit: () => showGoalEditor(context, existing: g),
                        onDelete: () => _delete(context, g),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: context.penny.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: context.text.labelSmall
                  ?.copyWith(color: context.penny.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: context.text.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: tabularFigures,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.currency,
    required this.now,
    required this.onAddSavings,
    required this.onEdit,
    required this.onDelete,
  });

  final Goal goal;
  final CurrencyInfo currency;
  final DateTime now;
  final VoidCallback onAddSavings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = goal.color;
    final suggested = goal.suggestedMonthlyMinor(now);
    final isDone = goal.isAchieved;

    return PennyCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CategoryIcons.of(goal.iconKey),
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.name,
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (goal.targetDate != null)
                      Text(
                        isDone
                            ? 'Target reached!'
                            : 'Deadline: ${DateUtilsX.dayMonthYear(goal.targetDate!)}',
                        style: context.text.bodySmall?.copyWith(
                          color: context.penny.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Edit goal'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: context.penny.expense),
                        const SizedBox(width: 10),
                        Text('Delete goal',
                            style: TextStyle(color: context.penny.expense)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Money.format(goal.savedMinor, currency)} of ${Money.format(goal.targetMinor, currency)}',
                style: context.text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${goal.percentage}%',
                  style: context.text.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal.progressRatio,
              minHeight: 8,
              backgroundColor: context.penny.border,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!isDone && suggested != null)
                Expanded(
                  child: Text(
                    'Save ${Money.format(suggested, currency)} / mo to reach on time',
                    style: context.text.bodySmall?.copyWith(
                      color: context.penny.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              else if (!isDone)
                Expanded(
                  child: Text(
                    '${Money.format(goal.remainingMinor, currency)} remaining',
                    style: context.text.bodySmall?.copyWith(
                      color: context.penny.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'Goal achieved! 🎯',
                    style: context.text.bodySmall?.copyWith(
                      color: context.penny.income,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!isDone)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: onAddSavings,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add savings'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

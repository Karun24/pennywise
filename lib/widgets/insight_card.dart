import 'package:flutter/material.dart';

import '../services/smart/insights_engine.dart';
import '../theme/theme_ext.dart';

IconData insightIcon(InsightTopic topic) => switch (topic) {
      InsightTopic.trend => Icons.trending_up_rounded,
      InsightTopic.category => Icons.donut_large_rounded,
      InsightTopic.average => Icons.calendar_today_rounded,
      InsightTopic.budget => Icons.account_balance_wallet_rounded,
      InsightTopic.anomaly => Icons.bolt_rounded,
      InsightTopic.savings => Icons.savings_rounded,
      InsightTopic.habit => Icons.lightbulb_rounded,
    };

Color insightColor(BuildContext context, InsightTone tone) => switch (tone) {
      InsightTone.positive => context.penny.income,
      InsightTone.info => context.penny.accent,
      InsightTone.warning => context.penny.warning,
      InsightTone.alert => context.penny.expense,
    };

/// Card showing one rule-based insight.
class InsightCard extends StatelessWidget {
  const InsightCard({super.key, required this.insight, this.width});

  final Insight insight;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final color = insightColor(context, insight.tone);
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: context.isDark ? 0.16 : 0.10),
            context.colors.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(insightIcon(insight.topic), size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  insight.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            insight.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../state/shell_controller.dart';
import '../theme/theme_ext.dart';

/// Bottom navigation: Home, Analytics, [Add], Budget, Settings.
/// The centre Add button is raised and uses the brand gradient.
class PennyBottomBar extends StatelessWidget {
  const PennyBottomBar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onAdd,
    this.profileBadge = false,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback onAdd;

  /// Shows a dot on Profile (e.g. when an app update is available).
  final bool profileBadge;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
            top: BorderSide(color: context.penny.border.withValues(alpha: 0.8))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                selected: current == AppTab.home,
                onTap: () => onSelect(AppTab.home),
              ),
              _NavItem(
                icon: Icons.insights_outlined,
                activeIcon: Icons.insights_rounded,
                label: 'Analytics',
                selected: current == AppTab.analytics,
                onTap: () => onSelect(AppTab.analytics),
              ),
              Expanded(child: Center(child: _AddButton(onTap: onAdd))),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                activeIcon: Icons.account_balance_wallet_rounded,
                label: 'Budget',
                selected: current == AppTab.budget,
                onTap: () => onSelect(AppTab.budget),
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profile',
                badge: profileBadge,
                selected: current == AppTab.settings,
                onTap: () => onSelect(AppTab.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  final bool badge;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.colors.primary : context.penny.textMuted;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? context.colors.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Badge(
                  isLabelVisible: badge,
                  smallSize: 8,
                  backgroundColor: context.penny.accent,
                  child: Icon(selected ? activeIcon : icon,
                      color: color, size: 22),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: context.text.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.penny.primaryGradient;
    return Semantics(
      button: true,
      label: 'Add transaction',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: g,
            ),
            boxShadow: [
              BoxShadow(
                color: g.first.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'theme.dart';

/// Kleines farbiges Label für die Domäne einer Übung oder eines Programms.
class DomainChip extends StatelessWidget {
  const DomainChip(this.domain, {super.key, this.compact = false});

  final String domain;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.domainColor(domain);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        domain,
        style: TextStyle(
          color: color,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Schlanker Fortschrittsbalken ohne Material-Rahmenwerk.
class ThinProgressBar extends StatelessWidget {
  const ThinProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 6,
  });

  /// 0..1
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Abschnittsüberschrift in Listen.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Leerer Zustand mit Handlungsaufforderung.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: scheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

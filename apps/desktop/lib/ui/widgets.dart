import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/reaper_actions.dart';
import '../state/reaper.dart';
import '../theme/app_theme.dart';

/// Color of warnings (missing plugins, duplicates).
const warningColor = Color(0xFFE5A04D);

/// Small console tag (status, alerts): mono capitals in a lit frame.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.xs),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.legend.copyWith(color: color, fontSize: 9.5),
    ),
  );
}

/// Status light: a small dot, glowing when [lit].
class Led extends StatelessWidget {
  const Led(this.color, {super.key, this.lit = true, this.size = 7});

  final Color color;
  final bool lit;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Motion.medium,
    curve: Motion.curve,
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: lit ? color : context.colors.border,
      boxShadow: [
        if (lit)
          BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: size),
      ],
    ),
  );
}

/// Button label hidden behind a small spinner while [busy], keeping the
/// button size.
class BusyLabel extends StatelessWidget {
  const BusyLabel(this.label, {super.key, required this.busy});

  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Opacity(opacity: busy ? 0 : 1, child: Text(label)),
      if (busy)
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
    ],
  );
}

/// Upper-case legend heading a section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: context.legend);
}

/// Runs [change] of a project file, after a confirmation when REAPER is
/// running (SPEC §5.7); failures are reported in a snackbar.
Future<bool> runProjectChange(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() change,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (await ref.read(reaperRunningProvider)()) {
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.reaperOpenTitle),
        content: Text(l10n.reaperOpenHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.continueAnyway),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
  }
  try {
    await change();
    return true;
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(l10n, error))),
    );
    return false;
  }
}

/// Opens [version] of [title] in REAPER; problems are reported in a
/// snackbar.
Future<void> openVersionInReaper(
  BuildContext context,
  WidgetRef ref,
  Title title,
  Version version,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!await ref.read(reaperActionsProvider).openVersion(title, version)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.reaperNotFound)));
    }
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(l10n, error))),
    );
  }
}

/// Text shown when an action fails with [error].
String failureMessage(AppLocalizations l10n, Object error) =>
    error is ProjectEncodingException
    ? l10n.projectEncodingFailed
    : l10n.actionFailed('$error');

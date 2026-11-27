import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../l10n/app_localizations.dart';

/// Displayed label of a status key (provided keys are translated).
String statusLabel(AppLocalizations l10n, String status) => switch (status) {
  'idea' => l10n.statusIdea,
  'writing' => l10n.statusWriting,
  'recording' => l10n.statusRecording,
  'mixing' => l10n.statusMixing,
  'done' => l10n.statusDone,
  _ => status,
};

/// Displayed level value: the reserved unassigned value is translated.
String levelValueLabel(AppLocalizations l10n, String value) =>
    value == Layout.unassigned ? l10n.unassigned : value;

String modeLabel(AppLocalizations l10n, LibraryMode mode) => switch (mode) {
  LibraryMode.local => l10n.modeLocal,
  LibraryMode.cloud => l10n.modeCloud,
  LibraryMode.collab => l10n.modeCollab,
};

/// Name shown for a title: its leaf level value (last one), else its folder
/// name.
String titleName(Title t) =>
    t.levels.values.lastOrNull ?? t.path.split('/').last;

/// Level values of a title above its leaf (e.g. artist and album).
List<String> parentLevels(Title t) => [
  if (t.levels.isNotEmpty)
    ...t.levels.values.take(t.levels.length - 1).where((v) => v.isNotEmpty),
];

/// The current time: fixed by the tests so that "this year" does not move.
@visibleForTesting
DateTime Function() currentTime = DateTime.now;

/// Short date: "Oct 28" this year, "Oct 2025" before.
String shortDate(AppLocalizations l10n, DateTime? date) => switch (date) {
  final d? when d.year == currentTime().year => DateFormat.MMMd(
    l10n.localeName,
  ).format(d),
  final d? => DateFormat.yMMM(l10n.localeName).format(d),
  null => '',
};

/// Sample rate of the latest dated version that has one; null when none.
int? latestSampleRate(Title t) {
  final dated = [...t.versions.where((v) => v.sampleRate != null)]
    ..sort((a, b) => b.modified.compareTo(a.modified));
  return dated.firstOrNull?.sampleRate;
}

/// Sample rate in kHz: `48 kHz`, `44.1 kHz`.
String sampleRateLabel(int hertz) {
  final khz = hertz / 1000;
  return '${khz.toStringAsFixed(khz == khz.roundToDouble() ? 0 : 1)} kHz';
}

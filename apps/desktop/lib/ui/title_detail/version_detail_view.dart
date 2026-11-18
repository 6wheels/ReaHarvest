import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_reaper/reaharvest_reaper.dart';
import 'package:reaharvest_rpp/reaharvest_rpp.dart';

import '../../l10n/app_localizations.dart';
import '../../state/navigation.dart';
import '../../state/version_detail.dart';
import '../../theme/app_theme.dart';
import '../formats.dart';
import '../widgets.dart';

/// Tracks shown before "Show more" (SPEC §5.3).
const trackLimit = 20;

/// Detailed view of the project at [path]: sample rate, tempo and signature
/// changes, length, tracks with their FX, referenced media (SPEC §5.3).
class VersionDetailView extends ConsumerWidget {
  const VersionDetailView(this.path, {super.key});

  /// Absolute path of the `.RPP`.
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(versionDetailProvider(path))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Text(
            l10n.projectUnreadable,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.colors.muted),
          ),
          data: (detail) => _Content(detail),
        );
  }
}

String _signature((int, int) s) => '${s.$1}/${s.$2}';

String _bpm(double bpm) =>
    bpm == bpm.roundToDouble() ? bpm.toInt().toString() : bpm.toString();

class _Content extends ConsumerWidget {
  const _Content(this.detail);

  final VersionDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = context.colors.muted;
    final cache = ref.watch(pluginCacheProvider).value;
    final facts = <(String, String)>[
      if (detail.sampleRate != null)
        (l10n.sampleRate, '${detail.sampleRate} Hz'),
      if (detail.tempo != null) (l10n.tempo, '${_bpm(detail.tempo!)} BPM'),
      if (detail.signature != null)
        (l10n.timeSignature, _signature(detail.signature!)),
      (l10n.songLength, formatLength(detail.length)),
      if (detail.reaperVersion != null)
        (l10n.reaperVersion, detail.reaperVersion!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.xl,
          runSpacing: Space.xs,
          children: [
            for (final (label, value) in facts)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label  ',
                      style: text.bodySmall?.copyWith(color: muted),
                    ),
                    TextSpan(text: value, style: text.bodyMedium),
                  ],
                ),
              ),
          ],
        ),
        if (detail.tempoChanges.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.tempoChanges),
          const SizedBox(height: Space.xs),
          for (final change in detail.tempoChanges)
            Text(
              [
                formatLength(change.position),
                if (change.tempo != null) '${_bpm(change.tempo!)} BPM',
                if (change.signature != null) _signature(change.signature!),
              ].join('  ·  '),
              style: text.bodyMedium,
            ),
        ],
        if (detail.tracks.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.tracks),
          const SizedBox(height: Space.xs),
          _Tracks(detail.tracks, cache),
        ],
        if (detail.media.isNotEmpty) ...[
          const SizedBox(height: Space.l),
          SectionLabel(l10n.referencedMedia),
          const SizedBox(height: Space.xs),
          for (final m in detail.media)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    m.size == null
                        ? Icons.error_outline_rounded
                        : Icons.check_rounded,
                    size: 16,
                    color: m.size == null ? warningColor : muted,
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(child: Text(m.reference, style: text.bodyMedium)),
                  Text(
                    m.size == null ? l10n.mediaAbsent : formatSize(m.size!),
                    style: text.bodySmall?.copyWith(
                      color: m.size == null ? warningColor : muted,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Tracks extends StatefulWidget {
  const _Tracks(this.tracks, this.cache);

  final List<RppTrack> tracks;
  final PluginCache? cache;

  @override
  State<_Tracks> createState() => _TracksState();
}

class _TracksState extends State<_Tracks> {
  bool _all = false;

  bool _missing(RppPlugin plugin) =>
      widget.cache?.status(plugin) == PluginStatus.missing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = context.colors.muted;
    final tracks = widget.tracks;
    final shown = _all ? tracks : tracks.take(trackLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in shown)
          Padding(
            padding: EdgeInsets.only(
              left: t.depth * Space.l,
              top: 2,
              bottom: 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4, right: Space.s),
                  decoration: BoxDecoration(
                    color: t.color == null ? null : _color(t.color!),
                    border: Border.all(color: muted),
                  ),
                ),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: t.name.isEmpty ? l10n.unnamedTrack : t.name,
                          style: text.bodyMedium,
                        ),
                        for (final plugin in t.plugins)
                          TextSpan(
                            text:
                                '   ${_missing(plugin) ? '⚠ ' : ''}'
                                '${plugin.name}',
                            style: text.bodySmall?.copyWith(
                              color: _missing(plugin) ? warningColor : muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!_all && tracks.length > trackLimit)
          TextButton(
            onPressed: () => setState(() => _all = true),
            child: Text(l10n.showMoreTracks(tracks.length - trackLimit)),
          ),
      ],
    );
  }
}

/// Flutter color of a REAPER native color (`0x00BBGGRR`).
Color _color(int native) => Color(
  0xFF000000 |
      (native & 0xFF) << 16 |
      (native >> 8 & 0xFF) << 8 |
      (native >> 16 & 0xFF),
);

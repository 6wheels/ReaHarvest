import 'ext_state.dart';
import 'tree.dart';

/// Chunk names that hold a plugin instance.
const _pluginChunks = {'VST', 'JS', 'CLAP', 'AU', 'DX', 'LV2'};

/// A plugin referenced by a track (track FX, input FX or take FX).
class RppPlugin {
  const RppPlugin({
    required this.kind,
    required this.name,
    required this.identifier,
  });

  /// Format as written by REAPER: `VST`, `VSTi`, `VST3`, `VST3i`, `CLAP`,
  /// `CLAPi`, `AU`, `AUi`, `JS`, `DX`, `LV2`…
  final String kind;

  /// Display name, e.g. `ReaEQ (Cockos)`, or the JS path for JS effects.
  final String name;

  /// What the plugin cache is keyed on: the plugin file name for VST,
  /// the JS path, the plugin id for CLAP/AU.
  final String identifier;

  @override
  bool operator ==(Object other) =>
      other is RppPlugin &&
      other.kind == kind &&
      other.name == name &&
      other.identifier == identifier;

  @override
  int get hashCode => Object.hash(kind, name, identifier);

  @override
  String toString() => '$kind: $name [$identifier]';
}

class RppTrack {
  const RppTrack({
    required this.name,
    required this.depth,
    required this.color,
    required this.plugins,
  });

  final String name;

  /// Folder depth, 0 for top-level tracks.
  final int depth;

  /// Native color value (Windows COLORREF `0x00BBGGRR`), null when the track
  /// has no custom color.
  final int? color;

  /// Deduplicated plugins, in first-seen order.
  final List<RppPlugin> plugins;
}

/// Read-only view of the project data ReaHarvest needs.
class RppProject {
  RppProject(this.document);

  factory RppProject.parse(String text) =>
      RppProject(RppDocument.parse(text));

  final RppDocument document;

  RppChunk get _root => document.root;

  String? _param(String name, [int i = 0]) {
    final p = _root.line(name)?.params;
    return (p == null || p.length <= i) ? null : p[i];
  }

  /// REAPER version that last saved the project, e.g. `7.84/win64`.
  String? get reaperVersion =>
      _root.params.length > 1 ? _root.params[1] : null;

  String? get title => _param('TITLE');
  String? get author => _param('AUTHOR');

  double? get tempo => double.tryParse(_param('TEMPO') ?? '');

  /// Time signature as `(numerator, denominator)`.
  (int, int)? get timeSignature {
    final num = int.tryParse(_param('TEMPO', 1) ?? '');
    final den = int.tryParse(_param('TEMPO', 2) ?? '');
    return (num == null || den == null) ? null : (num, den);
  }

  int? get sampleRate => int.tryParse(_param('SAMPLERATE') ?? '');

  /// Primary recording path (`RECORD_PATH`), relative or absolute.
  String? get recordPath => _param('RECORD_PATH');

  /// Render target (`RENDER_FILE`): empty, a folder or a file path.
  String? get renderFile => _param('RENDER_FILE');
  String? get renderPattern => _param('RENDER_PATTERN');

  String? get notes {
    final c = _root.chunk('NOTES');
    if (c == null) return null;
    return c.lines
        .map((l) => l.text.startsWith('|') ? l.text.substring(1) : l.text)
        .join('\n');
  }

  /// End of the last item, in seconds.
  double get length {
    var end = 0.0;
    for (final track in _root.chunksNamed('TRACK')) {
      for (final item in track.chunksNamed('ITEM')) {
        final pos =
            double.tryParse(item.line('POSITION')?.params.firstOrNull ?? '');
        final len =
            double.tryParse(item.line('LENGTH')?.params.firstOrNull ?? '');
        if (pos != null && len != null && pos + len > end) end = pos + len;
      }
    }
    return end;
  }

  List<RppTrack> get tracks {
    final result = <RppTrack>[];
    var depth = 0;
    for (final track in _root.chunksNamed('TRACK')) {
      final name = track.line('NAME')?.params.firstOrNull ?? '';
      final peak = int.tryParse(track.line('PEAKCOL')?.params.firstOrNull ?? '');
      final color =
          (peak != null && peak & 0x1000000 != 0) ? peak & 0xFFFFFF : null;
      final plugins = <RppPlugin>{};
      _collectPlugins(track, plugins);
      result.add(RppTrack(
        name: name,
        depth: depth < 0 ? 0 : depth,
        color: color,
        plugins: plugins.toList(),
      ));
      final delta = int.tryParse(
            track.line('ISBUS')?.params.elementAtOrNull(1) ?? '',
          ) ??
          0;
      depth += delta;
    }
    return result;
  }

  /// Plugins on the master track (`MASTERFXLIST`), deduplicated.
  List<RppPlugin> get masterPlugins {
    final master = _root.chunk('MASTERFXLIST');
    if (master == null) return const [];
    final plugins = <RppPlugin>{};
    _collectPlugins(master, plugins);
    return plugins.toList();
  }

  /// Every plugin used in the project (master and tracks), deduplicated.
  Set<RppPlugin> get allPlugins => {
        ...masterPlugins,
        for (final t in tracks) ...t.plugins,
      };

  /// Media file references (`FILE` lines of `SOURCE` chunks), deduplicated,
  /// as written in the project (relative or absolute).
  List<String> get mediaFiles {
    final files = <String>{};
    void visit(RppChunk c) {
      if (c.name == 'SOURCE') {
        final f = c.line('FILE')?.params.firstOrNull;
        if (f != null && f.isNotEmpty) files.add(f);
      }
      c.chunks.forEach(visit);
    }

    visit(_root);
    return files.toList();
  }

  /// Values of an `EXTSTATE` section, keys upper-cased as stored by REAPER.
  Map<String, String> extState(String section) {
    final s = _root.chunk('EXTSTATE')?.chunk(section.toUpperCase());
    return s == null ? const {} : readExtStateSection(s);
  }

  static void _collectPlugins(RppChunk chunk, Set<RppPlugin> out) {
    for (final c in chunk.chunks) {
      if (_pluginChunks.contains(c.name)) {
        final p = _plugin(c);
        if (p != null) out.add(p);
      } else {
        // FXCHAIN, FXCHAIN_REC, ITEM > TAKEFX, CONTAINER…
        _collectPlugins(c, out);
      }
    }
  }

  static RppPlugin? _plugin(RppChunk c) {
    final p = c.params;
    if (p.isEmpty) return null;
    if (c.name == 'JS') {
      return RppPlugin(kind: 'JS', name: p[0], identifier: p[0]);
    }
    // `"VST3: Name (Vendor)" file.vst3 …`, `"CLAP: Name (Vendor)" id …`
    final label = p[0];
    final sep = label.indexOf(': ');
    final kind = sep < 0 ? c.name : label.substring(0, sep);
    final name = sep < 0 ? label : label.substring(sep + 2);
    return RppPlugin(
      kind: kind,
      name: name,
      identifier: p.length > 1 ? p[1] : name,
    );
  }
}

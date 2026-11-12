import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/libraries.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'layout_labels.dart';
import 'media_plan_preview.dart';
import 'report_dialog.dart';

/// Issue kinds fixed in batch from the "To sort" page (SPEC §5.8 step 4).
const batchFixKinds = {
  ReportKind.titleTooHigh,
  ReportKind.misplacedLevel,
  ReportKind.unknownValue,
  ReportKind.projectTooDeep,
  ...normalizeKinds,
};

/// Issue kinds fixed by normalizing the media of the title of the project
/// (#69): the whole title is fixed at once, its media being shared.
const normalizeKinds = {
  ReportKind.mediaOutsidePool,
  ReportKind.recordPathNotMedia,
};

/// Title folder of the project [path] whose media are to normalize: its
/// folder, or the title of the pool holding it (a subproject).
String mediaTitleOf(String path) {
  final dir = p.posix.dirname(path);
  return p.posix.basename(dir).toLowerCase() == 'media'
      ? p.posix.dirname(dir)
      : dir;
}

/// Previews the batch fix of [issues], all of [kind] (dry run): each item
/// with its target, checked by default. Folders get optional values for
/// the levels above them, applied to every item (prefilled when the
/// proposals agree); unknown folders also get the level they belong to.
/// Projects too deep get their owner and the status deduced from their
/// status subfolder. Projects whose media are to normalize stand for
/// their title, whose planned operations are previewed. Returns the checked fixes by library, or null if
/// cancelled.
Future<Map<LibraryId, List<MigrationFix>>?> showFixDialog(
  BuildContext context,
  ReportKind kind,
  List<LibraryIssue> issues,
) => showDialog(context: context, builder: (_) => _FixDialog(kind, issues));

/// Status of the library deduced from the status subfolder [folder]: the
/// status whose key or label equals it, or starts with it (e.g. `mix`);
/// null if none.
String? proposeStatus(AppLocalizations l10n, String folder) {
  final name = folder.toLowerCase();
  for (final status in Title.defaultStatuses) {
    final label = statusLabel(l10n, status).toLowerCase();
    if (name == status || name == label) return status;
    if (name.length >= 3 &&
        (status.startsWith(name) || label.startsWith(name))) {
      return status;
    }
  }
  return null;
}

/// Existing values of level [i] of [layout] among the [titles] of
/// [libraries], under the values [above] (an empty value matches any).
List<String> levelValues(
  Iterable<Title> titles,
  Set<LibraryId> libraries,
  Layout layout,
  int i,
  List<String> above,
) {
  final keys = [for (final l in layout.levels) l.key];
  return {
    for (final t in titles)
      if (libraries.contains(t.libraryId) &&
          [
            for (final (j, value) in above.indexed)
              value.isEmpty || t.tags[keys[j]] == value,
          ].every((ok) => ok))
        ?t.tags[keys[i]],
  }.toList()..sort();
}

/// Whether moving the folder [path] of [library] to [target] merges it
/// with an existing folder (#81): [target] holds titles of [library].
/// Compared case-insensitively, like Windows paths.
bool mergesInto(
  Iterable<Title> titles,
  LibraryId library,
  String path,
  String target,
) {
  final folder = target.toLowerCase();
  if (folder == path.toLowerCase()) return false;
  return titles.any((t) {
    final title = t.path.toLowerCase();
    return t.libraryId == library &&
        (title == folder || title.startsWith('$folder/'));
  });
}

class _FixDialog extends ConsumerStatefulWidget {
  const _FixDialog(this.kind, this.issues);

  final ReportKind kind;
  final List<LibraryIssue> issues;

  @override
  ConsumerState<_FixDialog> createState() => _FixDialogState();
}

/// A project too deep: its member subfolder's member and its status
/// subfolder, if any.
typedef _Lift = ({Member? member, String? statusFolder});

class _FixDialogState extends ConsumerState<_FixDialog> {
  late final Set<int> _checked = {
    for (var i = 0; i < widget.issues.length; i++) i,
  };

  bool get _lifting => widget.kind == ReportKind.projectTooDeep;

  bool get _normalizing => normalizeKinds.contains(widget.kind);

  // Projects too deep.

  /// Owner of the projects without member subfolder; null when no library
  /// of the issues declares members (no owner is written, SPEC §4.2).
  MemberId? _owner;

  /// Status chosen for each status subfolder name.
  final _statuses = <String, String?>{};

  late final List<Member> _owners;
  late final List<_Lift> _lifts;

  // Media normalization.

  /// Plan of each title, by library and title; null while computed.
  Map<(LibraryId, String), MediaPlan>? _plans;

  Object? _previewError;

  // Folders.

  late final Layout _layout;

  /// Level of the unknown folders, chosen by the user (index in the
  /// layout); null for the other kinds, whose items carry their level.
  int? _level;

  /// Values of the intermediate levels; empty keeps each proposal.
  final _fields = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    final libraries = ref.read(indexedLibrariesProvider);
    if (_normalizing) {
      _preview();
      return;
    }
    if (_lifting) {
      final identity = ref.read(settingsProvider).identity;
      final members = {
        for (final i in widget.issues)
          for (final m in libraries[i.library]?.members ?? const <Member>[])
            m.id: m,
      };
      _owners = members.values.toList();
      _owner = members.containsKey(identity.memberId)
          ? identity.memberId
          : _owners.firstOrNull?.id;
      _lifts = [
        for (final i in widget.issues)
          _lift(i, libraries[i.library]?.members ?? const []),
      ];
      return;
    }
    _layout = libraries[widget.issues.first.library]!.layout!;
    if (widget.kind == ReportKind.unknownValue) {
      _level = _levelOf(widget.issues.first);
    }
    _fields.addAll([
      for (var j = 0; j < _layout.levels.length - 1; j++)
        TextEditingController(),
    ]);
    _prefill();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_lifting) return;
    // Proposed once, in the language of the interface.
    final l10n = AppLocalizations.of(context);
    for (final (member: _, :statusFolder) in _lifts) {
      if (statusFolder != null && !_statuses.containsKey(statusFolder)) {
        _statuses[statusFolder] = proposeStatus(l10n, statusFolder);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  /// Computes the normalization plan of the title of every issue.
  Future<void> _preview() async {
    final titles = <LibraryId, Set<String>>{};
    for (final issue in widget.issues) {
      titles
          .putIfAbsent(issue.library, () => {})
          .add(mediaTitleOf(issue.item.path));
    }
    final service = ref.read(libraryServiceProvider);
    try {
      final plans = <(LibraryId, String), MediaPlan>{};
      for (final MapEntry(key: library, value: paths) in titles.entries) {
        final found = await service.previewNormalization(library, [...paths]);
        for (final MapEntry(key: title, value: plan) in found.entries) {
          plans[(library, title)] = plan;
        }
      }
      if (mounted) setState(() => _plans = plans);
    } on Object catch (error) {
      if (mounted) setState(() => _previewError = error);
    }
  }

  /// Preview of the plans of the checked titles.
  List<Widget> _planPreviews(AppLocalizations l10n, TextStyle? muted) {
    if (_previewError case final error?) {
      return [Text(l10n.fixPreviewFailed('$error'), style: muted)];
    }
    final plans = _plans;
    if (plans == null) {
      return [
        Text(l10n.fixPreviewLoading, style: muted),
        const SizedBox(height: Space.s),
        const LinearProgressIndicator(),
      ];
    }
    final checked = {
      for (final i in _checked)
        (widget.issues[i].library, mediaTitleOf(widget.issues[i].item.path)),
    };
    return [
      for (final MapEntry(key: (library, title), value: plan) in plans.entries)
        if (checked.contains((library, title)))
          MediaPlanPreview(title: title, plan: plan),
    ];
  }

  /// Member and status subfolders of the project too deep [issue].
  _Lift _lift(LibraryIssue issue, List<Member> members) {
    final folder = p.posix.dirname(issue.item.path);
    final segments = folder.substring(issue.item.target!.length + 1).split('/');
    final member = members
        .where((m) => m.name.toLowerCase() == segments.first.toLowerCase())
        .firstOrNull;
    final rest = member == null ? segments : segments.skip(1);
    return (member: member, statusFolder: rest.lastOrNull);
  }

  /// Index in the layout of the level of the folder [issue].
  int _levelOf(LibraryIssue issue) =>
      _layout.levels.indexWhere((l) => l.key == issue.item.level!.key);

  /// Level index of the item [i]: the chosen one for unknown folders.
  int _levelOfItem(int i) => _level ?? _levelOf(widget.issues[i]);

  /// Proposed values of the levels above the item [i]: its target, else
  /// its current parents, `_Unassigned` for the missing ones.
  List<String> _proposed(int i) {
    final item = widget.issues[i].item;
    final count = _levelOfItem(i);
    final target = item.target?.split('/');
    if (target != null && target.length == count + 1) {
      return target.take(count).toList();
    }
    final parents = p.posix.dirname(item.path).split('/')
      ..removeWhere((s) => s == '.');
    return [
      for (var j = 0; j < count; j++)
        j < parents.length ? parents[j] : Layout.unassigned,
    ];
  }

  /// Number of level fields shown: the levels above the deepest item.
  int get _fieldCount =>
      [for (var i = 0; i < widget.issues.length; i++) _levelOfItem(i)]
          .reduce((a, b) => a > b ? a : b);

  /// Fills each field with the value proposed for every item, if they
  /// agree; empty otherwise.
  void _prefill() {
    final proposals = [
      for (var i = 0; i < widget.issues.length; i++) _proposed(i),
    ];
    for (final (j, field) in _fields.indexed) {
      final values = {
        for (final proposed in proposals)
          if (j < proposed.length) proposed[j],
      };
      field.text = values.length == 1 ? values.single : '';
    }
  }

  /// Target of the folder item [i]: the field values, else its proposals,
  /// then its name.
  String _target(int i) => [
    for (final (j, value) in _proposed(i).indexed)
      _fields[j].text.trim().isEmpty ? value : _fields[j].text.trim(),
    p.posix.basename(widget.issues[i].item.path),
  ].join('/');

  bool get _valid => _fields
      .take(_lifting || _normalizing ? 0 : _fieldCount)
      .map((f) => f.text.trim())
      .every((v) => v.isEmpty || isValidFolderName(v));

  MigrationFix _fix(int i) {
    final item = widget.issues[i].item;
    if (_normalizing) return NormalizeMedia(mediaTitleOf(item.path));
    if (!_lifting) return MoveFolder(item.path, _target(i));
    final status = _liftStatus(i);
    return LiftProject(
      item.path,
      item.target!,
      owner: _liftOwner(i)?.id,
      status: status,
      statusFolder: status == null ? _lifts[i].statusFolder : null,
    );
  }

  /// Owner of the lifted project [i]: its member subfolder, else the
  /// default owner when its library declares it, else the local member if
  /// declared, else its first member; none when its library declares no
  /// members.
  Member? _liftOwner(int i) {
    final library = widget.issues[i].library;
    final members = ref.read(indexedLibrariesProvider)[library]?.members;
    if (members == null || members.isEmpty) return null;
    final local = ref.read(settingsProvider).identity.memberId;
    Member? find(MemberId? id) => members.where((m) => m.id == id).firstOrNull;
    return _lifts[i].member ?? find(_owner) ?? find(local) ?? members.first;
  }

  String? _liftStatus(int i) {
    final folder = _lifts[i].statusFolder;
    return folder == null ? null : _statuses[folder];
  }

  /// Target, and for a project its owner and status, joined.
  String _details(AppLocalizations l10n, int i) {
    if (_normalizing) {
      return l10n.fixNormalize(mediaTitleOf(widget.issues[i].item.path));
    }
    if (!_lifting) {
      final issue = widget.issues[i];
      final target = _target(i);
      final merges = mergesInto(
        ref.read(titlesProvider),
        issue.library,
        issue.item.path,
        target,
      );
      return ['→ $target', if (merges) l10n.fixMerged].join(' · ');
    }
    final status = _liftStatus(i);
    final path = widget.issues[i].item.path;
    return [
      '→ ${widget.issues[i].item.target}',
      // Label of a version not adopted yet: its file name (SPEC §4.2).
      p.posix.basenameWithoutExtension(path),
      ?_liftOwner(i)?.name,
      status == null ? l10n.noStatus : statusLabel(l10n, status),
    ].join(' · ');
  }

  void _confirm() {
    final fixes = <LibraryId, List<MigrationFix>>{};
    for (final i in _checked.toList()..sort()) {
      final fix = _fix(i);
      final list = fixes.putIfAbsent(widget.issues[i].library, () => []);
      // One normalization per title.
      if (fix is NormalizeMedia && list.any((f) => f.path == fix.path)) {
        continue;
      }
      list.add(fix);
    }
    Navigator.of(context).pop(fixes);
  }

  List<Widget> _liftChoices(AppLocalizations l10n) => [
    if (_owner case final owner?)
      Choice<MemberId>(
        label: l10n.fixDefaultOwner,
        value: owner,
        options: {for (final m in _owners) m.id: m.name},
        onChanged: (id) => setState(() => _owner = id),
      ),
    for (final folder in _statuses.keys)
      Choice<String?>(
        label: l10n.fixStatusFor(folder),
        value: _statuses[folder],
        options: {
          null: l10n.noStatus,
          for (final s in Title.defaultStatuses) s: statusLabel(l10n, s),
        },
        onChanged: (s) => setState(() => _statuses[folder] = s),
      ),
  ];

  List<Widget> _folderChoices(AppLocalizations l10n) {
    final libraries = {for (final i in widget.issues) i.library};
    return [
      if (_level case final level?)
        Choice<int>(
          label: l10n.fixFoldersAre,
          value: level,
          options: {
            for (final (j, l) in _layout.levels.indexed)
              j: layoutLevelLabel(l10n, l),
          },
          onChanged: (j) => setState(() {
            _level = j;
            _prefill();
          }),
        ),
      for (var j = 0; j < _fieldCount; j++)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: LevelField(
            label: layoutLevelLabel(l10n, _layout.levels[j]),
            hint: l10n.fixKeepProposed,
            controller: _fields[j],
            options: () => levelValues(
              ref.read(titlesProvider),
              libraries,
              _layout,
              j,
              [for (final f in _fields.take(j)) f.text.trim()],
            ),
            error:
                _fields[j].text.trim().isEmpty ||
                    isValidFolderName(_fields[j].text.trim())
                ? null
                : l10n.invalidFolderName,
            onChanged: () => setState(() {}),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: context.colors.muted);
    return AlertDialog(
      title: Text(reportKindLabel(l10n, widget.kind)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.fixHint, style: muted),
              const SizedBox(height: Space.s),
              if (_lifting)
                ..._liftChoices(l10n)
              else if (!_normalizing)
                ..._folderChoices(l10n),
              const SizedBox(height: Space.s),
              for (final (i, issue) in widget.issues.indexed)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _checked.contains(i),
                  onChanged: (on) => setState(
                    () => on! ? _checked.add(i) : _checked.remove(i),
                  ),
                  title: Text(issue.item.path),
                  subtitle: Text(_details(l10n, i), style: muted),
                ),
              if (_normalizing) ...[
                const SizedBox(height: Space.s),
                ..._planPreviews(l10n, muted),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _checked.isEmpty || !_valid ? null : _confirm,
          child: Text(l10n.taskFix(_checked.length)),
        ),
      ],
    );
  }
}

/// Labeled dropdown of [options] (value -> label).
class Choice<T> extends StatelessWidget {
  const Choice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.s),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        DropdownButton<T>(
          value: value,
          items: [
            for (final MapEntry(:key, value: text) in options.entries)
              DropdownMenuItem(value: key, child: Text(text)),
          ],
          onChanged: (v) => onChanged(v as T),
        ),
      ],
    ),
  );
}

/// Text field of one layout level, with autocompletion on existing values.
class LevelField extends StatefulWidget {
  const LevelField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    required this.error,
    required this.onChanged,
    this.hint,
  });

  final String label;

  /// Shown while empty.
  final String? hint;
  final TextEditingController controller;
  final List<String> Function() options;
  final String? error;
  final VoidCallback onChanged;

  @override
  State<LevelField> createState() => _LevelFieldState();
}

class _LevelFieldState extends State<LevelField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
    textEditingController: widget.controller,
    focusNode: _focus,
    optionsBuilder: (value) {
      final typed = value.text.trim().toLowerCase();
      return widget.options().where((o) => o.toLowerCase().contains(typed));
    },
    onSelected: (_) => widget.onChanged(),
    fieldViewBuilder: (context, controller, focusNode, _) => TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.error,
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        color: context.colors.raised,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 420),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                ListTile(
                  dense: true,
                  title: Text(o),
                  onTap: () => onSelected(o),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

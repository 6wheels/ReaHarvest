import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/migration_actions.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'layout_labels.dart';
import 'media_plan_preview.dart';
import 'report_dialog.dart';

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

class _FixDialog extends ConsumerStatefulWidget {
  const _FixDialog(this.kind, this.issues);

  final ReportKind kind;
  final List<LibraryIssue> issues;

  @override
  ConsumerState<_FixDialog> createState() => _FixDialogState();
}

class _FixDialogState extends ConsumerState<_FixDialog> {
  late final Set<int> _checked = {
    for (var i = 0; i < widget.issues.length; i++) i,
  };

  bool get _lifting => widget.kind == ReportKind.projectTooDeep;

  bool get _normalizing => normalizeKinds.contains(widget.kind);

  /// What is proposed, in the language of the interface: made once the
  /// localizations are known, again when the level of unknown folders
  /// changes.
  FixProposals? _proposals;

  // Projects too deep.

  /// Owner of the projects without member subfolder; null when no library
  /// of the issues declares members (no owner is written, SPEC §4.2).
  MemberId? _owner;

  /// Status chosen for each status subfolder name.
  final _statuses = <String, String?>{};

  // Media normalization.

  /// Whether the plans are being computed.
  var _previewing = true;

  /// Plan of each title, by library and title.
  final _plans = <(LibraryId, String), MediaPlan>{};

  /// Error of the libraries whose plans could not be computed.
  final _previewErrors = <LibraryId, Object>{};

  /// Stops the preview computations still running.
  final _cancels = <Future<void> Function()>[];

  // Folders.

  /// Level of the unknown folders, chosen by the user (index in the
  /// layout); null for the other kinds, whose items carry their level.
  int? _level;

  /// Values of the intermediate levels; empty keeps each proposal.
  final _fields = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    if (_normalizing) _preview();
    if (_normalizing || _lifting) return;
    final layout = ref
        .read(indexedLibrariesProvider)[widget.issues.first.library]!
        .layout!;
    _fields.addAll([
      for (var j = 0; j < layout.levels.length - 1; j++)
        TextEditingController(),
    ]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_proposals != null) return;
    final proposals = _proposals = _propose();
    _level = proposals.level;
    _owner = proposals.owner;
    for (final item in proposals.items) {
      if (item.statusFolder case final folder?) {
        _statuses.putIfAbsent(folder, () => item.status);
      }
    }
    _prefill();
  }

  /// The proposals of the issues, the statuses labeled in the language of
  /// the interface.
  FixProposals _propose() {
    final l10n = AppLocalizations.of(context);
    return proposeFixes(
      widget.kind,
      [for (final i in widget.issues) (library: i.library, item: i.item)],
      libraries: ref.read(indexedLibrariesProvider),
      titles: ref.read(titlesProvider),
      statusLabels: {
        for (final s in Title.defaultStatuses) s: statusLabel(l10n, s),
      },
      identity: ref.read(settingsProvider).identity.memberId,
      level: _level,
    );
  }

  @override
  void dispose() {
    // The files read by a preview are closed before a fix moves them.
    for (final cancel in _cancels) {
      cancel();
    }
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  /// Computes the normalization plan of the title of every issue, the
  /// libraries side by side; a library that fails keeps its error.
  Future<void> _preview() async {
    final titles = <LibraryId, Set<String>>{};
    for (final issue in widget.issues) {
      titles
          .putIfAbsent(issue.library, () => {})
          .add(mediaTitleOf(issue.item.path));
    }
    final service = ref.read(migrationActionsProvider);
    await Future.wait([
      for (final MapEntry(key: library, value: paths) in titles.entries)
        () async {
          final preview = service.previewNormalization(library, [...paths]);
          _cancels.add(preview.cancel);
          try {
            final found = await preview.plans;
            for (final MapEntry(key: title, value: plan) in found.entries) {
              _plans[(library, title)] = plan;
            }
          } on Object catch (error) {
            _previewErrors[library] = error;
          }
        }(),
    ]);
    if (mounted) setState(() => _previewing = false);
  }

  bool get _waitingPreview => _normalizing && _previewing;

  /// Preview of the plans of the checked titles.
  List<Widget> _planPreviews(AppLocalizations l10n, TextStyle? muted) {
    if (_previewing) {
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
      for (final MapEntry(key: library, value: error) in _previewErrors.entries)
        if (checked.any((c) => c.$1 == library))
          Text(l10n.fixPreviewFailed('$error'), style: muted),
      for (final MapEntry(key: (library, title), value: plan) in _plans.entries)
        if (checked.contains((library, title)))
          MediaPlanPreview(
            key: ValueKey((library, title)),
            title: title,
            plan: plan,
          ),
    ];
  }

  /// Number of level fields shown: the levels above the deepest item.
  int get _fieldCount => _proposals!.items.fold(
    0,
    (count, item) => item.levels.length > count ? item.levels.length : count,
  );

  /// Fills each field with the value proposed for every item, if they
  /// agree; empty otherwise.
  void _prefill() {
    for (final (j, field) in _fields.indexed) {
      field.text = _proposals!.commonValues[j] ?? '';
    }
  }

  List<String> get _levelValues => [for (final f in _fields) f.text];

  bool get _valid => _fields
      .take(_fieldCount)
      .map((f) => f.text.trim())
      .every((v) => v.isEmpty || isValidFolderName(v));

  String? _liftStatus(FixProposal proposal) {
    final folder = proposal.statusFolder;
    return folder == null ? null : _statuses[folder];
  }

  /// Target, and for a project its owner and status, joined.
  String _details(AppLocalizations l10n, int i) {
    final proposals = _proposals!;
    final proposal = proposals.items[i];
    final issue = proposal.issue;
    if (_normalizing) return l10n.fixNormalize(mediaTitleOf(issue.item.path));
    if (!_lifting) {
      final target = folderTarget(proposal, _levelValues);
      final merges = mergesInto(
        ref.read(titlesProvider),
        issue.library,
        issue.item.path,
        target,
      );
      return ['→ $target', if (merges) l10n.fixMerged].join(' · ');
    }
    final status = _liftStatus(proposal);
    return [
      '→ ${proposal.target}',
      proposal.label,
      ?liftOwner(proposals, proposal, _owner)?.name,
      status == null ? l10n.noStatus : statusLabel(l10n, status),
    ].join(' · ');
  }

  void _confirm() {
    final proposals = _proposals!;
    Navigator.of(context).pop(
      buildFixes(widget.kind, proposals, (
        checked: _checked,
        levelValues: _levelValues,
        owner: _owner,
        statuses: _statuses,
      )),
    );
  }

  List<Widget> _liftChoices(AppLocalizations l10n) => [
    if (_owner case final owner?)
      Choice<MemberId>(
        label: l10n.fixDefaultOwner,
        value: owner,
        options: {for (final m in _proposals!.owners) m.id: m.name},
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
            for (final (j, l) in _proposals!.layout!.levels.indexed)
              j: layoutLevelLabel(l10n, l),
          },
          onChanged: (j) => setState(() {
            _level = j;
            _proposals = _propose();
            _prefill();
          }),
        ),
      for (var j = 0; j < _fieldCount; j++)
        Padding(
          padding: const EdgeInsets.only(top: Space.s),
          child: LevelField(
            label: layoutLevelLabel(l10n, _proposals!.layout!.levels[j]),
            hint: l10n.fixKeepProposed,
            controller: _fields[j],
            options: () => levelValues(
              ref.read(titlesProvider),
              libraries,
              _proposals!.layout!,
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
          // The operations are shown before they are confirmed.
          onPressed: _checked.isEmpty || !_valid || _waitingPreview
              ? null
              : _confirm,
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

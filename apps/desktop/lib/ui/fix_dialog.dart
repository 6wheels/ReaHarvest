import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_repository/reaharvest_repository.dart';

import '../l10n/app_localizations.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'labels.dart';
import 'report_dialog.dart';

/// Issue kinds fixed in batch from the "To sort" page (SPEC §5.8 step 4).
const batchFixKinds = {
  ReportKind.titleTooHigh,
  ReportKind.misplacedLevel,
  ReportKind.projectTooDeep,
};

/// Previews the batch fix of [issues], all of [kind] (dry run): each item
/// with its target, checked by default; for projects too deep, their owner
/// and the status deduced from their status subfolder. Returns the checked
/// fixes by library, or null if cancelled.
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

  /// Owner of the projects without member subfolder.
  late MemberId _owner;

  /// Status chosen for each status subfolder name.
  final _statuses = <String, String?>{};

  late final List<Member> _owners;
  late final List<_Lift> _lifts;

  bool get _lifting => widget.kind == ReportKind.projectTooDeep;

  @override
  void initState() {
    super.initState();
    final libraries = ref.read(indexedLibrariesProvider);
    final identity = ref.read(settingsProvider).identity;
    final members = {
      for (final i in widget.issues)
        for (final m in libraries[i.library]?.members ?? const <Member>[])
          m.id: m,
    };
    _owners = members.isEmpty
        ? [Member(identity.memberId, identity.displayName)]
        : members.values.toList();
    _owner = members.containsKey(identity.memberId)
        ? identity.memberId
        : _owners.first.id;
    _lifts = [
      for (final i in widget.issues)
        _lift(i, libraries[i.library]?.members ?? const []),
    ];
  }

  /// Member and status subfolders of the project too deep [issue].
  _Lift _lift(LibraryIssue issue, List<Member> members) {
    if (!_lifting) return (member: null, statusFolder: null);
    final folder = p.posix.dirname(issue.item.path);
    final segments = folder.substring(issue.item.target!.length + 1).split('/');
    final member = members
        .where((m) => m.name.toLowerCase() == segments.first.toLowerCase())
        .firstOrNull;
    final rest = member == null ? segments : segments.skip(1);
    return (member: member, statusFolder: rest.lastOrNull);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Proposed once, in the language of the interface.
    final l10n = AppLocalizations.of(context);
    for (final (member: _, :statusFolder) in _lifts) {
      if (statusFolder != null && !_statuses.containsKey(statusFolder)) {
        _statuses[statusFolder] = proposeStatus(l10n, statusFolder);
      }
    }
  }

  MigrationFix _fix(int i) {
    final item = widget.issues[i].item;
    if (!_lifting) return MoveFolder(item.path, item.target!);
    final (:member, :statusFolder) = _lifts[i];
    final status = statusFolder == null ? null : _statuses[statusFolder];
    return LiftProject(
      item.path,
      item.target!,
      owner: member?.id ?? _owner,
      status: status,
      statusFolder: status == null ? statusFolder : null,
    );
  }

  /// Target, owner and status of the item [i], joined.
  String _details(AppLocalizations l10n, int i) {
    final target = widget.issues[i].item.target!;
    if (!_lifting) return '→ $target';
    final (:member, :statusFolder) = _lifts[i];
    final owner = member ?? _owners.firstWhere((m) => m.id == _owner);
    final status = statusFolder == null ? null : _statuses[statusFolder];
    return [
      '→ $target',
      owner.name,
      status == null ? l10n.noStatus : statusLabel(l10n, status),
    ].join(' · ');
  }

  void _confirm() {
    final fixes = <LibraryId, List<MigrationFix>>{};
    for (final i in _checked.toList()..sort()) {
      fixes.putIfAbsent(widget.issues[i].library, () => []).add(_fix(i));
    }
    Navigator.of(context).pop(fixes);
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
              if (_lifting) ...[
                const SizedBox(height: Space.m),
                _Choice<MemberId>(
                  label: l10n.fixDefaultOwner,
                  value: _owner,
                  options: {for (final m in _owners) m.id: m.name},
                  onChanged: (id) => setState(() => _owner = id),
                ),
                for (final folder in _statuses.keys)
                  _Choice<String?>(
                    label: l10n.fixStatusFor(folder),
                    value: _statuses[folder],
                    options: {
                      null: l10n.noStatus,
                      for (final s in Title.defaultStatuses)
                        s: statusLabel(l10n, s),
                    },
                    onChanged: (s) => setState(() => _statuses[folder] = s),
                  ),
              ],
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
          onPressed: _checked.isEmpty ? null : _confirm,
          child: Text(l10n.taskFix(_checked.length)),
        ),
      ],
    );
  }
}

/// Labeled dropdown of [options] (value -> label).
class _Choice<T> extends StatelessWidget {
  const _Choice({
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/library_catalog.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

/// Edits the declared members of the library [entry] (SPEC §6.5).
Future<void> showMembers(BuildContext context, LibraryEntry entry) =>
    showDialog(context: context, builder: (_) => _MembersDialog(entry));

class _MembersDialog extends ConsumerStatefulWidget {
  const _MembersDialog(this.entry);

  final LibraryEntry entry;

  @override
  ConsumerState<_MembersDialog> createState() => _MembersDialogState();
}

class _MembersDialogState extends ConsumerState<_MembersDialog> {
  /// Members being edited, with their name field; null while loading.
  List<(MemberId, TextEditingController)>? _members;

  @override
  void initState() {
    super.initState();
    ref.read(libraryCatalogProvider).membersOf(widget.entry).then((members) {
      if (!mounted) return;
      // The person preparing the library is proposed as the first member.
      final identity = ref.read(settingsProvider).identity;
      final initial = members.isEmpty
          ? [Member(identity.memberId, identity.displayName)]
          : members;
      setState(() {
        _members = [
          for (final m in initial) (m.id, TextEditingController(text: m.name)),
        ];
      });
    });
  }

  @override
  void dispose() {
    for (final (_, name)
        in _members ?? const <(MemberId, TextEditingController)>[]) {
      name.dispose();
    }
    super.dispose();
  }

  /// Error of the name of member [i]: empty, or used by an earlier member.
  String? _error(AppLocalizations l10n, int i) {
    final members = _members!;
    final name = members[i].$2.text.trim().toLowerCase();
    if (name.isEmpty) return l10n.memberNameMissing;
    final earlier = members
        .take(i)
        .any((m) => m.$2.text.trim().toLowerCase() == name);
    return earlier ? l10n.memberNameUsed : null;
  }

  void _add() => setState(
    () => _members!.add((MemberId.generate(), TextEditingController())),
  );

  void _remove(int i) => setState(() => _members!.removeAt(i).$2.dispose());

  void _save() {
    final members = [
      for (final (id, name) in _members!) Member(id, name.text.trim()),
    ];
    Navigator.of(context).pop();
    ref.read(libraryCatalogProvider).setMembers(widget.entry, members);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final members = _members;
    final valid =
        members != null &&
        [for (var i = 0; i < members.length; i++) _error(l10n, i)]
            .every((e) => e == null);
    return AlertDialog(
      title: Text('${l10n.members} · ${widget.entry.displayName}'),
      content: SizedBox(
        width: 420,
        child: members == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.membersHint,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.colors.muted),
                    ),
                    for (final (i, (id, name)) in members.indexed)
                      Padding(
                        key: ValueKey(id),
                        padding: const EdgeInsets.only(top: Space.s),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: name,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: l10n.memberName,
                                  errorText: _error(l10n, i),
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: l10n.removeMember,
                              onPressed: () => _remove(i),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Space.s),
                    TextButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(l10n.addMember),
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
        FilledButton(onPressed: valid ? _save : null, child: Text(l10n.save)),
      ],
    );
  }
}

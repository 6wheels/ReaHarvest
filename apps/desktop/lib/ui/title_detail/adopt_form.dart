import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../widgets.dart';

/// Adoption of a version without metadata: its id written into the project,
/// its label and owner (chosen among the declared members; none when the
/// library declares none) into the title's node file (SPEC §4.2).
class Adopt extends ConsumerStatefulWidget {
  const Adopt(this.title, this.version, {super.key});

  final Title title;
  final Version version;

  @override
  ConsumerState<Adopt> createState() => _AdoptState();
}

class _AdoptState extends ConsumerState<Adopt> {
  final _label = TextEditingController();

  /// Owner picked among the declared members; null for the default.
  MemberId? _picked;

  var _busy = false;

  List<Member> get _members =>
      ref.watch(indexedLibrariesProvider)[widget.title.libraryId]?.members ??
      const [];

  /// Owner written on adoption: none when the library declares no members,
  /// else the picked member, the local member if declared, or the first
  /// declared member.
  MemberId? get _owner {
    final local = ref.watch(
      settingsProvider.select((s) => s.identity.memberId),
    );
    final members = _members;
    if (members.isEmpty) return null;
    return _picked ??
        (members.any((m) => m.id == local) ? local : members.first.id);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  bool get _ready => !_busy && _label.text.trim().isNotEmpty;

  Future<void> _adopt() async {
    if (!_ready) return;
    final owner = _owner;
    try {
      // Spinner once confirmed, while the project is rewritten.
      await runProjectChange(context, ref, () {
        setState(() => _busy = true);
        return ref
            .read(versionActionsProvider)
            .adopt(widget.title, widget.version, _label.text, owner: owner);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final members = _members;
    final owner = _owner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.toAdoptHint,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: context.colors.muted),
        ),
        const SizedBox(height: Space.s),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _adopt(),
                  decoration: InputDecoration(
                    labelText: l10n.versionLabel,
                    isDense: true,
                  ),
                ),
              ),
              if (members.isNotEmpty) ...[
                const SizedBox(width: Space.s),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<MemberId>(
                    initialValue: owner,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: l10n.filterOwner,
                      isDense: true,
                    ),
                    items: [
                      for (final m in members)
                        DropdownMenuItem(value: m.id, child: Text(m.name)),
                    ],
                    onChanged: (id) => setState(() => _picked = id),
                  ),
                ),
              ],
              const SizedBox(width: Space.s),
              FilledButton(
                onPressed: _ready ? _adopt : null,
                child: BusyLabel(l10n.adopt, busy: _busy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

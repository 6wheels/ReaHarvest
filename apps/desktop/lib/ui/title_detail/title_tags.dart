import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../to_sort/fix_dialog.dart';

/// Free tags of a title (SPEC §5.9): one chip each, removable, and a field
/// to add one, with autocompletion over the tags of the library.
class TitleTags extends ConsumerStatefulWidget {
  const TitleTags(this.title, {super.key});

  final Title title;

  @override
  ConsumerState<TitleTags> createState() => _TitleTagsState();
}

class _TitleTagsState extends ConsumerState<TitleTags> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(List<String> tags) =>
      ref.read(versionActionsProvider).setTags(widget.title, tags);

  void _add(String text) {
    _controller.clear();
    if (text.trim().isEmpty) return;
    _set([...widget.title.tags, text]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = widget.title.tags;
    final known = knownTags(ref.watch(titlesProvider));
    // One line, scrolling sideways: the header stays low.
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Text(l10n.tagsLabel.toUpperCase(), style: context.legend),
          const SizedBox(width: Space.s),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final tag in tags)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.s),
                    child: InputChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(tag),
                      deleteButtonTooltipMessage: l10n.tagRemove(tag),
                      onDeleted: () => _set([
                        for (final t in tags)
                          if (t != tag) t,
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 200,
            child: LevelField(
              label: l10n.tagAddHint,
              controller: _controller,
              options: () => [
                for (final t in known)
                  if (!tags.any((x) => x.toLowerCase() == t.toLowerCase())) t,
              ],
              error: null,
              dense: true,
              onChanged: () {},
              onSubmit: _add,
            ),
          ),
        ],
      ),
    );
  }
}

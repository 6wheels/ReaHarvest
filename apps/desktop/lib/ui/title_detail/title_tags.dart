import 'dart:async';

import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';

import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/tasks.dart';
import '../../state/version_actions.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import '../versions/version_ui_actions.dart';

/// Width of the field adding a tag, side of the button showing it.
const _fieldWidth = 160.0;
const _addSide = 18.0;

/// Free tags of a title (SPEC §5.9): one chip each, removable, and a small
/// "+" showing a field to add one, with autocompletion over the tags of the
/// library. Enter adds a tag and keeps the focus in the field; Escape or a
/// click outside hides it.
class TitleTags extends ConsumerStatefulWidget {
  const TitleTags(this.title, {super.key});

  final Title title;

  @override
  ConsumerState<TitleTags> createState() => _TitleTagsState();
}

class _TitleTagsState extends ConsumerState<TitleTags> {
  final _controller = TextEditingController();

  /// Whether the field adding a tag is shown.
  var _adding = false;

  void _hideField() => setState(() {
    _adding = false;
    _controller.clear();
  });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Runs [edit]; failures in the notification zone.
  Future<void> _edit(Future<void> Function(VersionActions) edit) async {
    final l10n = AppLocalizations.of(context);
    final tasks = ref.read(tasksProvider.notifier);
    try {
      await edit(ref.read(versionActionsProvider));
    } on Object catch (e) {
      fail(tasks, l10n, e);
    }
  }

  void _add(String text) {
    // Cleared once a picked option is set: the options then follow the
    // empty field.
    scheduleMicrotask(_controller.clear);
    if (text.trim().isEmpty) return;
    _edit((actions) => actions.addTag(widget.title, text));
  }

  /// Removes [tag] after confirmation: the tag is shared by the members.
  Future<void> _remove(String tag) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirm(
      context,
      title: l10n.tagRemoveTitle(tag),
      content: l10n.tagRemoveHint,
      action: l10n.tagRemoveAction,
    );
    if (confirmed != true || !mounted) return;
    await _edit((actions) => actions.removeTag(widget.title, tag));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tags = widget.title.tags;
    final library = widget.title.libraryId;
    final known = knownTags([
      for (final t in ref.watch(titlesProvider))
        if (t.libraryId == library) t,
    ]);
    // One line, scrolling sideways: the header stays low.
    return SizedBox(
      height: Sizes.field,
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
                    child: Center(
                      child: Pill(
                        tag,
                        uppercase: false,
                        deleteTooltip: l10n.tagRemove(tag),
                        onDeleted: () => _remove(tag),
                      ),
                    ),
                  ),
                // Right after the tags: a discreet "+", then its field.
                Center(
                  child: _adding
                      ? TextFieldTapRegion(
                          onTapOutside: (_) => _hideField(),
                          child: Focus(
                            // Leaving the field (Tab, a click in another
                            // field) discards the entry.
                            canRequestFocus: false,
                            skipTraversal: true,
                            onFocusChange: (focused) {
                              if (!focused) _hideField();
                            },
                            child: SizedBox(
                              width: _fieldWidth,
                              child: LevelField(
                                label: l10n.tagAddHint,
                                controller: _controller,
                                options: () => [
                                  for (final t in known)
                                    if (!tags.any(
                                      (x) => x.toLowerCase() == t.toLowerCase(),
                                    ))
                                      t,
                                ],
                                error: null,
                                compact: true,
                                autofocus: true,
                                onChanged: () {},
                                onSubmit: _add,
                                onCancel: _hideField,
                              ),
                            ),
                          ),
                        )
                      : Tooltip(
                          message: l10n.tagAddHint,
                          child: PressableSurface(
                            onTap: () => setState(() => _adding = true),
                            radius: Radii.xs,
                            child: const SizedBox.square(
                              dimension: _addSide,
                              child: Icon(Icons.add_rounded, size: IconSize.s),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

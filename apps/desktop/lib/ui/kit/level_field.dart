import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import 'surface.dart';

/// Bounds of the suggestions list of a [LevelField].
const _menuMin = 160.0;
const _menuMaxWidth = 360.0;
const _menuMax = 200.0;

/// Room kept under a field for its error.
const _errorRoom = 19.0;

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
    this.onSubmit,
    this.dense = false,
    this.compact = false,
    this.autofocus = false,
    this.onCancel,
    this.newValueHint,
  });

  final String label;

  /// Shown while empty.
  final String? hint;
  final TextEditingController controller;
  final List<String> Function() options;
  final String? error;
  final VoidCallback onChanged;

  /// Called once with the text when the user presses Enter or picks an
  /// option. Enter keeps the typed text (in the spelling of an option equal
  /// to it ignoring case), unless the user moved through the options with
  /// the arrow or page keys: it then picks the highlighted one.
  final ValueChanged<String>? onSubmit;

  /// Compact field, without the room kept for an error.
  final bool dense;

  /// Small field for a tag-sized place: smaller text and height, the label
  /// as a hint, and no room for an error.
  final bool compact;

  /// Takes the focus when shown.
  final bool autofocus;

  /// Called when the user presses Escape in the field.
  final VoidCallback? onCancel;

  /// Shown under the field, in place of the error, while its text is not
  /// empty and equals none of the [options] ignoring case (e.g. "This level
  /// will be created").
  final String? newValueHint;

  @override
  State<LevelField> createState() => _LevelFieldState();
}

class _LevelFieldState extends State<LevelField> {
  final _focus = FocusNode();

  /// Whether the options were browsed with the keyboard since the last
  /// edit.
  var _browsed = false;

  /// Whether the last Enter picked an option.
  var _picked = false;

  /// Whether Escape closed the suggestions since the last edit or browse.
  var _closed = false;

  static final _browsingKeys = {
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.pageUp,
  };

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      if (event is! KeyUpEvent && _browsingKeys.contains(event.logicalKey)) {
        _browsed = true;
        _closed = false;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          widget.onCancel != null) {
        // A first Escape only closes the suggestions, the next one cancels.
        if (!_closed && _suggestions(widget.controller.text).isNotEmpty) {
          _closed = true;
          return KeyEventResult.ignored;
        }
        widget.onCancel!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  Iterable<String> _suggestions(String text) {
    final typed = text.trim().toLowerCase();
    return widget.options().where((o) => o.toLowerCase().contains(typed));
  }

  /// Submits the typed text, in the spelling of an option equal to it
  /// ignoring case.
  void _submitTyped(TextEditingController controller) {
    final typed = controller.text.trim().toLowerCase();
    final same = widget.options().where((o) => o.toLowerCase() == typed);
    if (same.firstOrNull case final o? when o != controller.text) {
      controller.text = o;
      widget.onChanged();
    }
    widget.onSubmit?.call(controller.text);
  }

  /// [LevelField.newValueHint], while the text is a new value.
  String? get _newValueHint {
    final hint = widget.newValueHint;
    final typed = widget.controller.text.trim().toLowerCase();
    if (hint == null || widget.error != null || typed.isEmpty) return null;
    return widget.options().any((o) => o.toLowerCase() == typed) ? null : hint;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) => _suggestions(value.text),
      onSelected: (value) {
        _picked = true;
        _browsed = false;
        setState(() {});
        widget.onChanged();
        widget.onSubmit?.call(value);
      },
      // Up, down and the page keys move through the options, Enter then
      // picks the highlighted one, a first Escape hides them, and the next
      // one cancels, when the field can be cancelled.
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: widget.autofocus,
            style: widget.compact ? context.type.small : null,
            onChanged: (_) {
              _browsed = false;
              _closed = false;
              setState(() {});
              widget.onChanged();
            },
            // Enter keeps the focus: several values can be entered in a row.
            onEditingComplete: () {},
            onSubmitted: (_) {
              _picked = false;
              // Picks the highlighted option, when the options are shown.
              if (_browsed) onSubmitted();
              if (!_picked) _submitTyped(controller);
            },
            decoration: InputDecoration(
              labelText: widget.compact ? null : widget.label,
              hintText: widget.hint ?? (widget.compact ? widget.label : null),
              hintStyle: widget.compact
                  ? context.type.small.copyWith(color: context.colors.muted)
                  : null,
              isDense: true,
              errorText: widget.error,
              helperText: _newValueHint,
              contentPadding: widget.compact
                  ? const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: Space.sm,
                    )
                  : null,
            ),
          ),
      // A console menu, like the other ones of the application.
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: Space.xxs),
          child: Surface.panel(
            elevation: Elevation.menu,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: _menuMin,
                maxWidth: _menuMaxWidth,
                maxHeight: _menuMax,
              ),
              child: IntrinsicWidth(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, o) in options.indexed)
                        _Option(
                          highlighted:
                              AutocompleteHighlightedOption.of(context) == i,
                          onPressed: () => onSelected(o),
                          label: o,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Room kept for the error, under the field: the dialog keeps its size
    // and the suggestions stay glued to the input.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        field,
        SizedBox(
          height:
              widget.dense ||
                  widget.compact ||
                  widget.error != null ||
                  _newValueHint != null
              ? 0
              : MediaQuery.textScalerOf(context).scale(_errorRoom),
        ),
      ],
    );
  }
}

/// Option of a [LevelField]: lit like a hovered menu entry while
/// highlighted with the keyboard, and scrolled into view.
class _Option extends StatefulWidget {
  const _Option({
    required this.highlighted,
    required this.onPressed,
    required this.label,
  });

  final bool highlighted;
  final VoidCallback onPressed;
  final String label;

  @override
  State<_Option> createState() => _OptionState();
}

class _OptionState extends State<_Option> {
  @override
  void didUpdateWidget(_Option old) {
    super.didUpdateWidget(old);
    if (widget.highlighted && !old.highlighted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MenuItemButton(
      onPressed: widget.onPressed,
      style: widget.highlighted
          ? MenuItemButton.styleFrom(
              backgroundColor: c.accent.withValues(alpha: Alpha.faint),
              foregroundColor: c.accent,
            )
          : null,
      child: Text(widget.label),
    );
  }
}

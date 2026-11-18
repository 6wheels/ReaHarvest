import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../widgets.dart';

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
        SizedBox(
          width: 200,
          child: Dropdown<T>(
            value: value,
            options: options,
            onChanged: onChanged,
          ),
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
    this.onSubmit,
    this.dense = false,
  });

  final String label;

  /// Shown while empty.
  final String? hint;
  final TextEditingController controller;
  final List<String> Function() options;
  final String? error;
  final VoidCallback onChanged;

  /// Called with the text when the user presses Enter or picks an option.
  /// Enter keeps the typed text (in the spelling of an option equal to it
  /// ignoring case), unless the user moved through the options with the
  /// arrow keys: it then picks the highlighted one.
  final ValueChanged<String>? onSubmit;

  /// Compact field, without the room kept for an error.
  final bool dense;

  @override
  State<LevelField> createState() => _LevelFieldState();
}

class _LevelFieldState extends State<LevelField> {
  final _focus = FocusNode();

  /// Whether the options were browsed with the arrow keys since the last
  /// edit.
  var _browsed = false;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      if (event is! KeyUpEvent &&
          (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowUp)) {
        _browsed = true;
      }
      return KeyEventResult.ignored;
    };
  }

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
    onSelected: (value) {
      widget.onChanged();
      widget.onSubmit?.call(value);
    },
    // Up and down move through the options, Enter then picks the
    // highlighted one, Escape hides them.
    fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (_) {
            _browsed = false;
            widget.onChanged();
          },
          onSubmitted: (value) {
            if (_browsed) {
              onSubmitted();
            } else {
              final typed = controller.text.trim().toLowerCase();
              final same = widget.options().where(
                (o) => o.toLowerCase() == typed,
              );
              if (same.firstOrNull case final o? when o != controller.text) {
                controller.text = o;
                widget.onChanged();
              }
            }
            widget.onSubmit?.call(controller.text);
          },
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            // Room kept for the error: the dialog keeps its size.
            helperText: widget.dense ? null : ' ',
            isDense: widget.dense,
            errorText: widget.error,
          ),
        ),
    // A console menu, like the other ones of the application.
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Material(
          color: context.colors.surface,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.s),
            side: BorderSide(color: context.colors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 160,
              maxWidth: 360,
              maxHeight: 200,
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
              backgroundColor: c.accent.withValues(alpha: 0.10),
              foregroundColor: c.accent,
            )
          : null,
      child: Text(widget.label),
    );
  }
}

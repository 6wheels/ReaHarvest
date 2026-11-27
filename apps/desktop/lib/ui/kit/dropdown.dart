import 'package:material_ui/material_ui.dart' hide Title;

import '../../theme/app_theme.dart';
import 'choice_light.dart';
import 'disclosure.dart';
import 'menu_focus.dart';

/// Drop-down field: a text field look (same height as the fields and the
/// buttons) opening a console menu of [options] (value -> label), the
/// current one lit and focused.
class Dropdown<T> extends StatefulWidget {
  const Dropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final T? value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? label;

  /// Dimmed and inert when false; it keeps its size.
  final bool enabled;

  @override
  State<Dropdown<T>> createState() => _DropdownState<T>();
}

class _DropdownState<T> extends State<Dropdown<T>> {
  /// The current entry, or the first one.
  final _entry = FocusNode();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = widget.value;
    final options = widget.options;
    final focused = options.containsKey(value)
        ? value
        : options.keys.firstOrNull;
    final anchor = MenuAnchor(
      alignmentOffset: const Offset(0, Space.xxs),
      onOpen: () => focusMenuEntry(_entry),
      menuChildren: [
        for (final MapEntry(:key, value: text) in options.entries)
          MenuItemButton(
            focusNode: key == focused ? _entry : null,
            leadingIcon: ChoiceLight(checked: key == value),
            onPressed: () => widget.onChanged(key),
            child: Text(text),
          ),
      ],
      builder: (context, controller, _) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: InputDecorator(
            // A null value can be an option of its own (e.g. "No status").
            isEmpty: value == null && !options.containsKey(null),
            isFocused: controller.isOpen,
            decoration: InputDecoration(
              labelText: widget.label,
              suffixIcon: Disclosure(
                controller.isOpen ? Disclosure.up : Disclosure.down,
                color: controller.isOpen ? c.accent : c.muted,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: IconSize.action,
                minHeight: 0,
              ),
            ),
            child: Text(
              options[value] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
    return widget.enabled
        ? anchor
        : ExcludeFocus(
            child: IgnorePointer(
              child: Opacity(opacity: Alpha.medium, child: anchor),
            ),
          );
  }
}

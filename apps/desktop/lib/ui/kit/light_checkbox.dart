import 'package:flutter/material.dart' hide Title;

import 'choice_light.dart';

/// Side of the click target, wider than the light drawn at its center.
const _target = 40.0;

/// Checkbox lit like a [ChoiceLight]: a null [value] shows a partial
/// selection (select all of a group). Its click target is wider than the
/// light.
class LightCheckbox extends StatelessWidget {
  const LightCheckbox({
    super.key,
    required this.value,
    required this.tooltip,
    required this.onPressed,
  });

  final bool? value;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    checked: value ?? false,
    mixed: value == null,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: ChoiceLight(checked: value),
      style: const ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(_target)),
      ),
    ),
  );
}

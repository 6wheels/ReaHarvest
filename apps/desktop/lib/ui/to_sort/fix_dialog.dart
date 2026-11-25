import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../kit/kit.dart';

/// Width of the drop-down of a choice.
const _fieldWidth = 200.0;

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
          width: _fieldWidth,
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

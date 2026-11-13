import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';

class Item extends StatelessWidget {
  const Item({
    required this.title,
    required this.subtitle,
    this.details = const [],
    this.action,
    this.selected,
    this.onSelected,
    super.key,
  });

  /// Whether the item is selected; null if it cannot be.
  final bool? selected;
  final ValueChanged<bool>? onSelected;

  final String title;
  final String subtitle;

  /// Lines under the subtitle (expected level, proposed place).
  final List<String> details;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: Space.s),
      padding: const EdgeInsets.all(Space.m),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected case final value?)
            Padding(
              padding: const EdgeInsets.only(right: Space.s),
              child: Checkbox(
                value: value,
                semanticLabel: title,
                onChanged: (on) => onSelected?.call(on!),
              ),
            ),
          Expanded(child: _content(context)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (subtitle.isNotEmpty)
          Text(subtitle, style: text.bodySmall?.copyWith(color: c.muted)),
        for (final line in details) Text(line, style: text.bodySmall),
        if (action case final action?) ...[
          const SizedBox(height: Space.s),
          Align(alignment: Alignment.centerRight, child: action),
        ],
      ],
    );
  }
}

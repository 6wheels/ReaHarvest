import 'package:flutter/material.dart' hide Title;

import '../../theme/app_theme.dart';
import '../widgets.dart';

/// Entry of the "To sort" list, like a rack strip: a square light to select
/// it (when it can be), its name and place, detail readouts and its action
/// at the end. The whole strip toggles the selection; a selected strip has
/// a lit edge.
class Item extends StatefulWidget {
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
  State<Item> createState() => _ItemState();
}

class _ItemState extends State<Item> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selected = widget.selected;
    final lit = selected ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs + 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: lit ? c.accent.withValues(alpha: 0.07) : c.surface,
            borderRadius: BorderRadius.circular(Radii.s),
            border: Border.all(
              color: lit
                  ? c.accent.withValues(alpha: 0.45)
                  : _hovered
                  ? c.muted.withValues(alpha: 0.6)
                  : c.border,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.s),
              onTap: selected == null
                  ? null
                  : () => widget.onSelected?.call(!selected),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Lit edge of the selected strip.
                    AnimatedContainer(
                      duration: Motion.fast,
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: lit ? c.accent : Colors.transparent,
                    ),
                    if (selected != null)
                      Padding(
                        padding: const EdgeInsets.only(left: Space.s + 2),
                        child: Center(
                          child: Semantics(
                            checked: selected,
                            label: widget.title,
                            child: ChoiceLight(checked: selected),
                          ),
                        ),
                      ),
                    Expanded(child: _content(context)),
                    if (widget.action case final action?)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: Center(child: action),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.m - 4, 10, Space.m, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.readout.copyWith(fontSize: 11),
            ),
          ],
          if (widget.details.isNotEmpty) ...[
            const SizedBox(height: Space.xs + 2),
            for (final line in widget.details)
              Text(
                line,
                style: TextStyle(color: c.text, fontSize: 12, height: 1.4),
              ),
          ],
        ],
      ),
    );
  }
}

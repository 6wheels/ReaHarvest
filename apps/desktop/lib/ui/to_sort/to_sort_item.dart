import 'package:material_ui/material_ui.dart' hide Title;

import '../../theme/app_theme.dart';
import '../kit/kit.dart';

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
      padding: const EdgeInsets.only(top: Space.sm),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.curve,
          decoration: BoxDecoration(
            color: lit ? c.accent.withValues(alpha: Alpha.faint) : c.surface,
            borderRadius: BorderRadius.circular(Radii.s),
            border: Border.all(
              color: lit
                  ? c.accent.withValues(alpha: Alpha.medium)
                  : _hovered
                  ? c.muted.withValues(alpha: Alpha.strong)
                  : c.border,
            ),
          ),
          child: PressableSurface(
            dimDisabled: false,
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
                    width: Sizes.bar,
                    margin: const EdgeInsets.symmetric(vertical: Space.sm),
                    color: lit ? c.accent : Colors.transparent,
                  ),
                  if (selected != null)
                    Padding(
                      padding: const EdgeInsets.only(left: Space.md),
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
    );
  }

  Widget _content(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.ml, Space.md, Space.m, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.item,
          ),
          if (widget.subtitle.isNotEmpty) ...[
            const SizedBox(height: Space.xxs),
            Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.readoutSmall,
            ),
          ],
          if (widget.details.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            for (final line in widget.details)
              Text(
                line,
                style: context.type.caption.copyWith(height: Leading.loose),
              ),
          ],
        ],
      ),
    );
  }
}

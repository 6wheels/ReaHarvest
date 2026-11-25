import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'disclosure.dart';
import 'pressable_surface.dart';

/// Indent of the content under the title: past the triangle and the icon.
const _indent = Space.l + Space.s;

/// Least height of the header.
const _headerHeight = 50.0;

/// Foldable section: a header (triangle, optional [leading] icon, [title])
/// showing or hiding the [children] under it.
class DisclosureTile extends StatefulWidget {
  const DisclosureTile({
    super.key,
    required this.title,
    required this.children,
    this.leading,
    this.initiallyExpanded = false,
  });

  final Widget title;
  final List<Widget> children;
  final Widget? leading;
  final bool initiallyExpanded;

  @override
  State<DisclosureTile> createState() => _DisclosureTileState();
}

class _DisclosureTileState extends State<DisclosureTile> {
  late var _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        expanded: _open,
        child: PressableSurface(
          onTap: () => setState(() => _open = !_open),
          radius: Radii.xs,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _headerHeight),
            child: Row(
              children: [
                Disclosure(_open ? Disclosure.down : Disclosure.right),
                const SizedBox(width: Space.xs),
                if (widget.leading case final leading?) ...[
                  leading,
                  const SizedBox(width: Space.s),
                ],
                Expanded(
                  child: DefaultTextStyle(
                    style: context.type.item,
                    child: widget.title,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_open)
        Padding(
          padding: const EdgeInsets.only(left: _indent, bottom: Space.s),
          // The content is a step below the title.
          child: DefaultTextStyle(
            style: context.type.caption,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.children,
            ),
          ),
        ),
    ],
  );
}

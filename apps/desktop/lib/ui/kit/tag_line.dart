import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import 'pill.dart';

/// Free tags of a title on one line, read only (SPEC §5.9): neutral
/// [Pill]s of the width they need, as many as fit, then a "+N" for the
/// others. Never taller than a pill, never wider than its constraints.
class TagLine extends StatelessWidget {
  const TagLine(this.tags, {super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final style = context.type.legendSmall;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double measure(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width + pillPadding * 2 + pillBorder * 2;
      painter.dispose();
      return w;
    }

    final widths = <String, double>{};
    double width(String label) => widths[label] ??= measure(label);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        // The most tags that fit with the "+N" of the others after them.
        var shown = 0;
        var used = 0.0;
        for (var i = 0; i < tags.length; i++) {
          used += width(tags[i]) + (i == 0 ? 0 : Space.xs);
          final rest = tags.length - i - 1;
          final more = rest == 0 ? 0.0 : Space.xs + width('+$rest');
          if (used + more > available) break;
          shown = i + 1;
        }
        // At least one tag, clipped when it is wider than the line.
        if (shown == 0) shown = 1;
        final rest = tags.length - shown;
        return ClipRect(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs,
            children: [
              // Each pill has the width it needs, but the lone first tag of
              // a short line, which is cut.
              for (var i = 0; i < shown; i++)
                if (shown == 1)
                  Flexible(child: Pill(tags[i], uppercase: false))
                else
                  Pill(tags[i], uppercase: false),
              if (rest > 0) Pill('+$rest', uppercase: false),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart' hide Title;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/library_scans.dart';
import '../../theme/app_theme.dart';
import '../over_library.dart';
import 'to_sort_list.dart';

/// Opens the "To sort" page over the library (SPEC §5.2).
Future<void> openToSort(BuildContext context) =>
    Navigator.of(context).push(overLibraryRoute((_) => const ToSortPage()));

/// Issues of the libraries grouped by kind, with a counter per kind
/// (SPEC §5.2, §5.8 step 3), and a guided move for misplaced projects. Back with the back button, Escape or
/// the mouse back button.
class ToSortPage extends StatelessWidget {
  const ToSortPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BackNavigation(
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.m,
                Space.m,
                Space.xl,
                Space.m,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.back,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const SizedBox(width: Space.s),
                  Text(
                    l10n.toSort,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  Consumer(
                    builder: (context, ref, _) => Tooltip(
                      message: l10n.fullScanTooltip,
                      child: TextButton.icon(
                        onPressed: () =>
                            ref.read(libraryScansProvider).scanAll(full: true),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l10n.fullScan),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.colors.border),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: const ToSortList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

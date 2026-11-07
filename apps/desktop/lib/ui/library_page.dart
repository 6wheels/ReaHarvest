import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'filter_bar.dart';
import 'settings_dialog.dart';
import 'side_panel.dart';
import 'title_card.dart';
import 'title_views.dart';

/// Main window: the library (SPEC §5.2). Search bar at the top, filters
/// below, then the titles as cards, list or tree, and the side panel.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(visibleTitlesProvider);
    final navigation = ref.watch(navigationProvider);
    final hasTitles = ref.watch(titlesProvider).isNotEmpty;
    final panel = ref.watch(panelProvider);
    final l10n = AppLocalizations.of(context);

    final Widget content;
    if (!hasTitles) {
      content = _Message(
        key: const ValueKey('empty'),
        icon: Icons.album_outlined,
        title: l10n.emptyLibraryTitle,
        hint: l10n.emptyLibraryHint,
      );
    } else if (titles.isEmpty) {
      content = _Message(
        key: const ValueKey('noResults'),
        icon: Icons.search_off_rounded,
        title: navigation.query.trim().isEmpty
            ? l10n.noFilterResults
            : l10n.noResults(navigation.query.trim()),
      );
    } else {
      content = switch (navigation.displayMode) {
        DisplayMode.cards => GridView.builder(
          key: const ValueKey('grid'),
          padding: const EdgeInsets.fromLTRB(
            Space.xl,
            Space.s,
            Space.xl,
            Space.xl,
          ),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisSpacing: Space.l,
            crossAxisSpacing: Space.l,
          ),
          itemCount: titles.length,
          itemBuilder: (_, i) => _Appear(
            key: ValueKey(titles[i].id),
            index: i,
            child: TitleCard(
              titles[i],
              selected: panel == TitlePanel(titles[i].id),
              onTap: () => ref
                  .read(panelProvider.notifier)
                  .toggle(TitlePanel(titles[i].id)),
            ),
          ),
        ),
        DisplayMode.list => TitleList(titles, key: const ValueKey('list')),
        DisplayMode.tree => TitleTree(titles, key: const ValueKey('tree')),
      };
    }

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              ref.read(panelProvider.notifier).close(),
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.xl,
                      Space.l,
                      Space.l,
                      Space.m,
                    ),
                    child: Row(
                      children: [
                        // Balances the gear so that the search bar stays
                        // centered.
                        const SizedBox(width: 40),
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: const _SearchBar(),
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        const _SettingsButton(),
                      ],
                    ),
                  ),
                  if (hasTitles) const FilterBar(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Motion.medium,
                      child: content,
                    ),
                  ),
                ],
              ),
            ),
            _PanelHost(panel),
          ],
        ),
      ),
    );
  }
}

/// Slides the side panel in and out, keeping its content while closing.
class _PanelHost extends StatefulWidget {
  const _PanelHost(this.content);

  final PanelContent? content;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  PanelContent? _shown;

  @override
  Widget build(BuildContext context) {
    _shown = widget.content ?? _shown;
    final open = widget.content != null;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: open ? sidePanelWidth : 0),
      duration: Motion.medium,
      curve: Motion.curve,
      onEnd: () {
        if (!open) setState(() => _shown = null);
      },
      builder: (context, width, _) => SizedBox(
        width: width,
        child: _shown == null
            ? null
            : ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: sidePanelWidth,
                  maxWidth: sidePanelWidth,
                  child: SidePanel(_shown!),
                ),
              ),
      ),
    );
  }
}

/// Search bar, focused on startup; shows the restored or applied query.
class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  late final _controller = TextEditingController(
    text: ref.read(navigationProvider).query,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(navigationProvider.select((n) => n.query), (_, query) {
      if (query != _controller.text) _controller.text = query;
    });
    final c = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      controller: _controller,
      autofocus: true,
      onChanged: ref.read(navigationProvider.notifier).setQuery,
      style: Theme.of(context).textTheme.bodyLarge,
      cursorColor: c.accent,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context).searchHint,
        hintStyle: TextStyle(color: c.muted),
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: c.raised,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: border(c.border),
        focusedBorder: border(c.accent.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _SettingsButton extends StatefulWidget {
  const _SettingsButton();

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: IconButton(
      tooltip: AppLocalizations.of(context).settings,
      onPressed: () => showSettings(context),
      icon: AnimatedRotation(
        turns: _hovered ? 0.125 : 0,
        duration: Motion.medium,
        curve: Motion.curve,
        child: const Icon(Icons.settings_outlined),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
  });

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: c.muted.withValues(alpha: 0.6)),
            const SizedBox(height: Space.m),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            if (hint case final hint?) ...[
              const SizedBox(height: Space.s),
              Text(
                hint,
                style: text.bodyMedium?.copyWith(color: c.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fade and rise on first display, staggered for the first cards.
class _Appear extends StatefulWidget {
  const _Appear({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _t = CurvedAnimation(parent: _controller, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    final delay = widget.index < 24 ? widget.index * 30 : 0;
    Future.delayed(Duration(milliseconds: delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _t,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(_t),
      child: widget.child,
    ),
  );
}

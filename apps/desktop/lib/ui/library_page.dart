import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart' as domain show Title;
import 'package:reaharvest_domain/reaharvest_domain.dart' show NodeId;
import 'package:reaharvest_library/reaharvest_library.dart';

import '../l10n/app_localizations.dart';
import '../state/navigation.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';
import 'filter_bar.dart';
import 'settings_dialog.dart';
import 'overview.dart';
import 'title_detail.dart';
import 'title_card.dart';
import 'title_views.dart';

/// Main window: the library (SPEC §5.2). Search bar at the top, filters
/// below, then the titles as cards, list or tree, and the overview docked
/// at the bottom.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titles = ref.watch(visibleTitlesProvider);
    final navigation = ref.watch(navigationProvider);
    final hasTitles = ref.watch(titlesProvider).isNotEmpty;
    // Without titles, the filter bar still leads to the items to sort.
    final hasIssues = ref.watch(issuesProvider).isNotEmpty;
    final overview = ref.watch(overviewProvider);
    final pinned = navigation.overviewPinned;
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
        DisplayMode.cards => _TitleGrid(titles, key: const ValueKey('grid')),
        DisplayMode.list => TitleList(titles, key: const ValueKey('list')),
        DisplayMode.tree => TitleTree(titles, key: const ValueKey('tree')),
      };
    }

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              ref.read(overviewProvider.notifier).close(),
        },
        // The content takes its final size at once and the overview slides
        // over it: no relayout of the titles during the animation. Pinned,
        // the titles end above the overview; otherwise it floats over them
        // and a click outside of it closes it (cards and controls win their
        // own clicks).
        child: Stack(
          children: [
            Positioned.fill(
              bottom: overview == null || !pinned
                  ? 0
                  : overviewHeight + Space.l,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: pinned || overview == null
                    ? null
                    : ref.read(overviewProvider.notifier).close,
                child: RepaintBoundary(
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
                                  constraints: const BoxConstraints(
                                    maxWidth: 560,
                                  ),
                                  child: const _SearchBar(),
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.s),
                            const _SettingsButton(),
                          ],
                        ),
                      ),
                      if (hasTitles || hasIssues) const FilterBar(),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: Motion.medium,
                          child: content,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: Space.xl,
              right: Space.xl,
              bottom: Space.l,
              height: overviewHeight,
              child: _OverviewHost(overview),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slides the overview up and down, keeping its content while closing.
class _OverviewHost extends StatefulWidget {
  const _OverviewHost(this.title);

  final NodeId? title;

  @override
  State<_OverviewHost> createState() => _OverviewHostState();
}

class _OverviewHostState extends State<_OverviewHost> {
  NodeId? _shown;

  @override
  Widget build(BuildContext context) {
    _shown = widget.title ?? _shown;
    final open = widget.title != null;
    return IgnorePointer(
      ignoring: !open,
      child: AnimatedSlide(
        offset: Offset(0, open ? 0 : 1.2),
        duration: Motion.medium,
        curve: Motion.curve,
        onEnd: () {
          if (!open) setState(() => _shown = null);
        },
        child: AnimatedOpacity(
          opacity: open ? 1 : 0,
          duration: Motion.medium,
          curve: Motion.curve,
          child: _shown == null
              ? const SizedBox()
              : RepaintBoundary(child: Overview(_shown!)),
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
      // Enter opens the detail of the title in the overview.
      onSubmitted: (_) {
        if (ref.read(overviewProvider) case final title?) {
          openTitleDetail(context, title);
        }
      },
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

/// Size of a title card.
const _cardSize = 264.0;

/// Titles as cards. When the results change, the cards leaving fade out
/// first, then the grid reflows and the new or moved cards fade in.
class _TitleGrid extends ConsumerStatefulWidget {
  const _TitleGrid(this.titles, {super.key});

  final List<domain.Title> titles;

  @override
  ConsumerState<_TitleGrid> createState() => _TitleGridState();
}

class _TitleGridState extends ConsumerState<_TitleGrid> {
  late var _shown = widget.titles;
  var _leaving = const <Object>{};
  Timer? _timer;

  @override
  void didUpdateWidget(_TitleGrid old) {
    super.didUpdateWidget(old);
    if (identical(widget.titles, old.titles)) return;
    _timer?.cancel();
    final kept = {for (final t in widget.titles) t.id};
    final leaving = {
      for (final t in _shown)
        if (!kept.contains(t.id)) t.id,
    };
    if (leaving.isEmpty) {
      _shown = widget.titles;
      _leaving = const {};
      return;
    }
    _leaving = leaving;
    _timer = Timer(Motion.fast, () {
      if (mounted) {
        setState(() {
          _shown = widget.titles;
          _leaving = const {};
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(overviewProvider);
    final toAdopt = ref.watch(toAdoptCountsProvider);
    final titles = _shown;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fixed card size: resizing only changes the column count, the
        // remaining width stays on the right.
        final available = constraints.maxWidth - 2 * Space.xl;
        final columns = ((available + Space.l) / (_cardSize + Space.l))
            .floor()
            .clamp(1, 1 << 10);
        final used = columns * _cardSize + (columns - 1) * Space.l;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            Space.xl,
            Space.s,
            (constraints.maxWidth - Space.xl - used).clamp(
              Space.xl,
              double.infinity,
            ),
            Space.xl,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Space.l,
            crossAxisSpacing: Space.l,
          ),
          itemCount: titles.length,
          itemBuilder: (_, i) => _Appear(
            key: ValueKey(titles[i].id),
            id: titles[i].id,
            index: i,
            results: titles,
            child: AnimatedOpacity(
              opacity: _leaving.contains(titles[i].id) ? 0 : 1,
              duration: Motion.fast,
              child: TitleCard(
                titles[i],
                selected: overview == titles[i].id,
                toAdopt: toAdopt[titles[i].id] ?? 0,
                onTap: () =>
                    ref.read(overviewProvider.notifier).toggle(titles[i].id),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Card entrance: staggered fade and rise on the first display of the
/// library, short fade when the results change (search, filters). Cards
/// rebuilt with the same results (scroll, resize) show up at once.
class _Appear extends StatefulWidget {
  const _Appear({
    super.key,
    required this.id,
    required this.index,
    required this.results,
    required this.child,
  });

  final Object id;
  final int index;

  /// Displayed titles this card belongs to.
  final List<Object> results;

  final Widget child;

  /// Last [results] seen, and the titles already shown for them.
  static List<Object>? _results;
  static var _initial = true;
  static final _seen = <Object>{};

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final _t = CurvedAnimation(parent: _controller, curve: Motion.curve);
  var _rise = true;

  @override
  void initState() {
    super.initState();
    if (!identical(widget.results, _Appear._results)) {
      _Appear._initial = _Appear._results == null;
      _Appear._results = widget.results;
      _Appear._seen.clear();
    }
    if (!_Appear._seen.add(widget.id)) {
      _controller.value = 1;
      return;
    }
    if (!_Appear._initial) {
      _rise = false;
      _controller.duration = Motion.medium;
      _controller.forward();
      return;
    }
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
    child: _rise
        ? SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(_t),
            child: widget.child,
          )
        : widget.child,
  );
}

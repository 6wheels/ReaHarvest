import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_index/reaharvest_index.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

// Ports and resources: overridden with the concrete implementations in
// `main()` only (SPEC §7.2), and with fakes in tests.

final settingsFileProvider = Provider<SettingsFile>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Settings loaded before the first frame, to start without flicker.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final localIndexProvider = Provider<LocalIndex>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Application settings; every change is saved.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> change(AppSettings Function(AppSettings) edit) {
    state = edit(state);
    return persist(state);
  }

  @protected
  Future<void> persist(AppSettings settings) =>
      ref.read(settingsFileProvider).save(settings);
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Incremented after every index change, to refresh what reads the index.
class IndexRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final indexRevisionProvider = NotifierProvider<IndexRevision, int>(
  IndexRevision.new,
);

/// What a title card shows. [bpm] and [status] are null until known.
typedef TitleView = ({Title title, int? bpm, String? status});

/// All indexed titles, served from the index (SPEC §8: startup view).
final titleViewsProvider = Provider<List<TitleView>>((ref) {
  ref.watch(indexRevisionProvider);
  return [
    for (final t in ref.watch(localIndexProvider).titles())
      (title: t, bpm: null, status: t.status),
  ];
});

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final _titleSearchProvider = Provider<TitleSearch>(
  (ref) => TitleSearch([for (final v in ref.watch(titleViewsProvider)) v.title]),
);

/// Titles matching the search query, best first.
final visibleTitlesProvider = Provider<List<TitleView>>((ref) {
  final views = {for (final v in ref.watch(titleViewsProvider)) v.title.id: v};
  return [
    for (final t
        in ref.watch(_titleSearchProvider).search(ref.watch(searchQueryProvider)))
      views[t.id]!,
  ];
});

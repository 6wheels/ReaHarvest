import 'package:reaharvest_domain/reaharvest_domain.dart' show LibraryId;

/// One writer at a time per library (SPEC §5.2): the tasks, scans and
/// version actions of a library run one after the other, in the order
/// asked; libraries are independent. A turn is not re-entrant: a body must
/// not ask the turn of its own library again.
class LibraryTurns {
  /// End of the last body asked, by library.
  final _last = <LibraryId, Future<void>>{};

  /// Number of bodies running or waiting, by library.
  final _pending = <LibraryId, int>{};

  /// Whether a body of [library] runs or waits.
  bool isBusy(LibraryId library) => _pending.containsKey(library);

  /// Runs [body] once the bodies of [library] asked before it have ended,
  /// failed or not. Returns its result.
  Future<T> run<T>(LibraryId library, Future<T> Function() body) {
    _pending[library] = (_pending[library] ?? 0) + 1;
    final result = (_last[library] ?? Future<void>.value())
        .then((_) => body())
        .whenComplete(() {
          if ((_pending[library] = _pending[library]! - 1) == 0) {
            _pending.remove(library);
            _last.remove(library);
          }
        });
    _last[library] = result.then((_) {}, onError: (_) {});
    return result;
  }
}

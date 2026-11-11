import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest_domain/reaharvest_domain.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

/// Saves held until completed by the test; the first one can fail.
class SlowSettings extends SettingsNotifier {
  final pending = <(double, Completer<void>)>[];

  @override
  Future<void> persist(AppSettings settings) {
    final done = Completer<void>();
    pending.add((settings.textScale, done));
    return done.future;
  }
}

void main() {
  test('saves the settings one after the other, in order', () async {
    final notifier = SlowSettings();
    final container = ProviderContainer(
      overrides: [
        initialSettingsProvider.overrideWithValue(
          AppSettings(identity: const LocalIdentity(MemberId('M'), 'Alice')),
        ),
        settingsProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);
    container.read(settingsProvider);

    final first = notifier.change((s) => s.copyWith(textScale: 1.1));
    final second = notifier.change((s) => s.copyWith(textScale: 1.2));
    final third = notifier.change((s) => s.copyWith(textScale: 1.3));
    // Applied at once, saved one at a time.
    expect(container.read(settingsProvider).textScale, 1.3);
    await pumpEventQueue();
    expect(notifier.pending.map((p) => p.$1), [1.1]);

    // A failed save does not stop the next ones.
    notifier.pending.last.$2.completeError(StateError('disk full'));
    await expectLater(first, throwsStateError);
    await pumpEventQueue();
    expect(notifier.pending.map((p) => p.$1), [1.1, 1.2]);
    notifier.pending.last.$2.complete();
    await second;
    await pumpEventQueue();
    expect(notifier.pending.map((p) => p.$1), [1.1, 1.2, 1.3]);
    notifier.pending.last.$2.complete();
    await third;
  });
}

import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest/state/window_behavior.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

/// Keeps settings in memory instead of writing a file.
class MemorySettings extends SettingsNotifier {
  final saved = <AppSettings>[];

  @override
  Future<void> persist(AppSettings settings) async => saved.add(settings);
}

class FakeShell implements WindowShell {
  final calls = <String>[];

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> destroy() async => calls.add('destroy');

  @override
  Future<void> setTray(TrayLabels? labels) async =>
      calls.add(labels == null ? 'tray off' : 'tray ${labels.open}');
}

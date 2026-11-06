import 'package:reaharvest/state/providers.dart';
import 'package:reaharvest_library/reaharvest_library.dart';

/// Keeps settings in memory instead of writing a file.
class MemorySettings extends SettingsNotifier {
  final saved = <AppSettings>[];

  @override
  Future<void> persist(AppSettings settings) async => saved.add(settings);
}

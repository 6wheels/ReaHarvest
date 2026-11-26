import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/no_hard_coded_style.dart';
import 'src/no_raw_material_widget.dart';

// coverage:ignore-start
// Plugin entry point read by the analysis server, exercised by
// `flutter analyze`: nothing to unit test.

/// Entry point read by the analysis server (`plugins:` in the app
/// `analysis_options.yaml`).
final plugin = ReaHarvestLints();

class ReaHarvestLints extends Plugin {
  @override
  String get name => 'reaharvest_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(NoHardCodedStyle());
    registry.registerWarningRule(NoRawMaterialWidget());
  }
}
// coverage:ignore-end

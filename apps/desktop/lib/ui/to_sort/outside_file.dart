import 'package:material_ui/material_ui.dart' hide Title;
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../kit/kit.dart';
import 'to_sort_item.dart';

/// A file found outside any title (SPEC §5.8 step 3: an orphan node file,
/// a document beside the titles), with a field choosing one of the
/// [titles] of its library (paths) and an action attaching it there
/// ([onAttach], given the title as typed in the spelling of [titles]).
class OutsideFile extends StatefulWidget {
  const OutsideFile({
    super.key,
    required this.path,
    required this.titles,
    required this.onAttach,
    this.library,
  });

  /// Library path of the file.
  final String path;
  final List<String> titles;
  final ValueChanged<String> onAttach;

  /// Name of its library, when several are shown.
  final String? library;

  @override
  State<OutsideFile> createState() => _OutsideFileState();
}

class _OutsideFileState extends State<OutsideFile> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// The title typed, in the spelling of [OutsideFile.titles]; null if it
  /// is none of them.
  String? get _chosen {
    final typed = _title.text.trim().toLowerCase();
    return widget.titles.where((t) => t.toLowerCase() == typed).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final folder = p.posix.dirname(widget.path);
    final chosen = _chosen;
    return Item(
      title: p.posix.basename(widget.path),
      subtitle: [?widget.library, if (folder != '.') folder].join(' · '),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.s,
        children: [
          Expanded(
            child: LevelField(
              label: l10n.outsideFileTitle,
              controller: _title,
              options: () => widget.titles,
              error: chosen == null && _title.text.trim().isNotEmpty
                  ? l10n.outsideFileNoTitle
                  : null,
              onChanged: () => setState(() {}),
            ),
          ),
          OutlinedButton(
            onPressed: chosen == null ? null : () => widget.onAttach(chosen),
            child: Text(l10n.outsideFileAttach),
          ),
        ],
      ),
    );
  }
}

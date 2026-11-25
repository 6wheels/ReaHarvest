import 'package:material_ui/material_ui.dart' hide Title;

/// Focuses [node] once the menu it belongs to is shown, so that the arrow
/// keys move through the entries, Enter or Space activate one and Escape
/// closes the menu.
void focusMenuEntry(FocusNode node) =>
    WidgetsBinding.instance.addPostFrameCallback((_) => node.requestFocus());

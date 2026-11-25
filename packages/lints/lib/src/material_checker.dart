import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'style_checker.dart' show ShorthandType;

/// The Material widgets allowed outside the kit: the ones styled by
/// `buildTheme` (see its doc comment in `lib/theme/app_theme.dart`).
const allowedMaterialWidgets = {
  'MaterialApp',
  'Scaffold',
  'Dialog',
  'AlertDialog',
  'Card',
  'Divider',
  'VerticalDivider',
  'SnackBar',
  'Tooltip',
  'Scrollbar',
  'Slider',
  'SegmentedButton',
  'Theme',
  'TextField',
  'SelectableText',
  'MenuAnchor',
  'MenuItemButton',
  'SubmenuButton',
  'FilledButton',
  'OutlinedButton',
  'TextButton',
  'IconButton',
  'LinearProgressIndicator',
  'CircularProgressIndicator',
  'LicensePage',
};

/// The constructions in [unit] (the file at [path]) of a type that is not in
/// [allowedMaterialWidgets], with the name of the type. Nothing in the kit
/// (`lib/ui/kit/`) nor outside the app `lib/`. The caller keeps the ones that
/// are Material widgets: it needs the resolved types.
List<(AstNode, String)> findWidgetCandidates(
  String path,
  CompilationUnit unit, {
  ShorthandType? shorthandType,
}) {
  final p = path.replaceAll('\\', '/');
  const lib = 'apps/desktop/lib/';
  final at = p.lastIndexOf(lib);
  if (at < 0) return const [];
  final rel = p.substring(at + lib.length);
  if (rel.startsWith('ui/kit/') || rel.startsWith('theme/')) {
    return const [];
  }
  final visitor = _CreationVisitor(shorthandType);
  unit.accept(visitor);
  return visitor.found;
}

class _CreationVisitor extends RecursiveAstVisitor<void> {
  _CreationVisitor(this.shorthandType);

  final ShorthandType? shorthandType;
  final found = <(AstNode, String)>[];

  void _add(AstNode node, String type) {
    if (!allowedMaterialWidgets.contains(type)) found.add((node, type));
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _add(node, node.constructorName.type.name.lexeme);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _addShorthand(node);
    super.visitDotShorthandInvocation(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    _addShorthand(node);
    super.visitDotShorthandConstructorInvocation(node);
  }

  /// `.new()`: the type is the one of the context.
  void _addShorthand(Expression node) {
    final type = shorthandType?.call(node);
    if (type != null) _add(node, type);
  }

  static bool _isTypeName(String name) {
    final first = name.replaceFirst(RegExp(r'^_+'), '');
    return first.isNotEmpty &&
        first[0] == first[0].toUpperCase() &&
        first[0] != first[0].toLowerCase();
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Before resolution, `Card()` and `ListTile.divideTiles()` are invocations.
    // A function or a variable (lower case) is not a type.
    final target = node.target;
    final name = target == null
        ? node.methodName.name
        : target is SimpleIdentifier
        ? target.name
        : null;
    if (name != null && _isTypeName(name)) _add(node, name);
    super.visitMethodInvocation(node);
  }
}

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Where a file stands for the style rule.
enum StyleZone {
  /// Not checked: outside the app `lib/`, the theme, the showcase, generated.
  unchecked,

  /// The kit: numeric literals allowed, `Color`, `Colors` and `TextStyle` not.
  kit,

  /// Everything else in the app `lib/`: all checks.
  strict,
}

/// The zone of the file at [path].
StyleZone styleZoneOf(String path) {
  final p = path.replaceAll('\\', '/');
  const lib = 'apps/desktop/lib/';
  final at = p.lastIndexOf(lib);
  if (at < 0) return StyleZone.unchecked;
  final rel = p.substring(at + lib.length);
  if (rel.startsWith('theme/') ||
      rel.startsWith('l10n/') ||
      rel == 'main_showcase.dart' ||
      rel == 'showcase_tokens.dart') {
    return StyleZone.unchecked;
  }
  return rel.startsWith('ui/kit/') ? StyleZone.kit : StyleZone.strict;
}

/// The name of the type a dot shorthand (`.all(8)`) stands for, null when it
/// is not known (it comes from the resolved context type).
typedef ShorthandType = String? Function(Expression shorthand);

/// The nodes of [unit] (the file at [path]) holding a hard-coded style value.
List<AstNode> findStyleViolations(
  String path,
  CompilationUnit unit, {
  ShorthandType? shorthandType,
}) {
  final zone = styleZoneOf(path);
  if (zone == StyleZone.unchecked) return const [];
  final visitor = _StyleVisitor(
    strict: zone == StyleZone.strict,
    shorthandType: shorthandType,
  );
  unit.accept(visitor);
  return visitor.violations;
}

class _StyleVisitor extends RecursiveAstVisitor<void> {
  _StyleVisitor({required this.strict, this.shorthandType});

  final bool strict;
  final ShorthandType? shorthandType;
  final violations = <AstNode>[];

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.prefix.name == 'Colors' && node.identifier.name != 'transparent') {
      violations.add(node);
    }
    if (strict &&
        node.prefix.name == 'FontWeight' &&
        _isNamedArgument(node, 'fontWeight')) {
      violations.add(node);
    }
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.name.lexeme;
    final named = node.constructorName.name?.name;
    _call(node, type, named, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _shorthand(node, node.memberName.name);
    super.visitDotShorthandInvocation(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    _shorthand(node, node.constructorName.name);
    super.visitDotShorthandConstructorInvocation(node);
  }

  /// `.all(8)`: the type is the one of the context.
  void _shorthand(InvocationExpression node, String member) {
    final type = shorthandType?.call(node);
    if (type == null) return;
    _call(node, type, member == 'new' ? null : member, node.argumentList);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Before resolution, `Color(0)` and `EdgeInsets.all(8)` are invocations.
    final target = node.target;
    if (target == null) {
      _call(node, node.methodName.name, null, node.argumentList);
    } else if (target is SimpleIdentifier) {
      _call(node, target.name, node.methodName.name, node.argumentList);
    }
    final method = node.methodName.name;
    if (strict && method == 'withValues') {
      _literalIn(node.argumentList, 'alpha');
    } else if (strict && method == 'withOpacity') {
      _literalIn(node.argumentList, null);
    }
    super.visitMethodInvocation(node);
  }

  /// A construction of [type] (named constructor or static [named]).
  void _call(AstNode node, String type, String? named, ArgumentList args) {
    final isColor =
        type == 'Color' && (named == null || named.startsWith('from'));
    if (isColor || (type == 'TextStyle' && named == null)) {
      violations.add(node);
    }
    if (!strict) return;
    switch (type) {
      case 'EdgeInsets' || 'EdgeInsetsDirectional' || 'BorderRadius':
        _literalIn(args, null);
      case 'Radius' when named == 'circular' || named == 'elliptical':
        _literalIn(args, null);
      case 'Duration' when named == null && _isStyleDuration(node):
        violations.add(node);
      case 'SizedBox' when named == null:
        _literalIn(args, 'width');
        _literalIn(args, 'height');
      case 'Icon' when named == null:
        _literalIn(args, 'size');
    }
  }

  @override
  void visitNamedArgument(NamedArgument node) {
    if (strict &&
        node.name.lexeme == 'fontSize' &&
        _hasNumber(node.argumentExpression)) {
      violations.add(node);
    }
    // `fontWeight: .bold`: the dot shorthand of FontWeight.
    if (strict &&
        node.name.lexeme == 'fontWeight' &&
        node.argumentExpression is DotShorthandPropertyAccess) {
      violations.add(node.argumentExpression);
    }
    super.visitNamedArgument(node);
  }

  /// Reports a numeric literal in the argument [name], or in any argument
  /// when [name] is null.
  void _literalIn(ArgumentList args, String? name) {
    for (final arg in args.arguments) {
      if (name != null && !(arg is NamedArgument && arg.name.lexeme == name)) {
        continue;
      }
      if (_hasNumber(arg.argumentExpression)) violations.add(arg);
    }
  }

  /// A duration given to a style argument (`duration:`, `waitDuration:`,
  /// `delay:`), not a timer or a piece of data.
  static bool _isStyleDuration(AstNode node) {
    final parent = node.parent;
    if (parent is! NamedArgument) return false;
    final name = parent.name.lexeme.toLowerCase();
    return name.contains('duration') || name.contains('delay');
  }

  static bool _isNamedArgument(AstNode node, String name) {
    final parent = node.parent;
    return parent is NamedArgument && parent.name.lexeme == name;
  }

  static bool _hasNumber(Expression expression) {
    final finder = _NumberFinder();
    expression.accept(finder);
    return finder.found;
  }
}

class _NumberFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitIntegerLiteral(IntegerLiteral node) {
    if (node.value != 0) found = true;
  }

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    if (node.value != 0) found = true;
  }
}

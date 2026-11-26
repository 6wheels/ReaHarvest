import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'style_checker.dart';

// coverage:ignore-start
// Thin glue to the analysis server: the logic is in [findStyleViolations],
// tested on its own; the glue is exercised by `flutter analyze`.

/// Reports the hard-coded style values of `apps/desktop/lib/` (CLAUDE.md, UI).
class NoHardCodedStyle extends AnalysisRule {
  static const code = LintCode(
    'no_hard_coded_style',
    'Hard-coded style value: use the theme tokens.',
    correctionMessage: 'Take the value from lib/theme/ or use a kit component.',
  );

  NoHardCodedStyle()
    : super(
        name: 'no_hard_coded_style',
        description: 'Forbids hard-coded colors, text styles and metrics.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final NoHardCodedStyle rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = context.currentUnit?.file.path;
    if (path == null) return;
    for (final violation in findStyleViolations(
      path,
      node,
      shorthandType: (e) => e.staticType?.element?.name,
    )) {
      rule.reportAtNode(violation);
    }
  }
}
// coverage:ignore-end

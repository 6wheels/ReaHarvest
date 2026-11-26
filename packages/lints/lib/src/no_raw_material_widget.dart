import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart';

import 'material_checker.dart';

// coverage:ignore-start
// Thin glue to the analysis server: the candidates come from
// [findWidgetCandidates], tested on its own; this keeps the ones whose
// resolved type is a Material widget. Exercised by `flutter analyze`.

/// Reports the Material widgets outside the kit and the closed list
/// (CLAUDE.md, UI).
class NoRawMaterialWidget extends AnalysisRule {
  static const code = LintCode(
    'no_raw_material_widget',
    'Raw Material widget: use a kit component.',
    correctionMessage: 'Use the kit, or a widget styled by buildTheme.',
  );

  NoRawMaterialWidget()
    : super(
        name: 'no_raw_material_widget',
        description: 'Forbids Material widgets outside the kit.',
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

  final NoRawMaterialWidget rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final path = context.currentUnit?.file.path;
    if (path == null) return;
    for (final (creation, _) in findWidgetCandidates(
      path,
      node,
      shorthandType: (e) => e.staticType?.element?.name,
    )) {
      final element = switch (creation) {
        InstanceCreationExpression() => creation.constructorName.type.element,
        Expression() => creation.staticType?.element,
        _ => null,
      };
      if (_isMaterialWidget(element)) rule.reportAtNode(creation);
    }
  }

  static bool _isMaterialWidget(Element? element) {
    if (element is! InterfaceElement) return false;
    final uri = element.library.uri.toString();
    if (!uri.startsWith('package:material_ui/') &&
        !uri.startsWith('package:flutter/src/material/')) {
      return false;
    }
    return element.allSupertypes.any((t) => t.element.name == 'Widget');
  }
}
// coverage:ignore-end

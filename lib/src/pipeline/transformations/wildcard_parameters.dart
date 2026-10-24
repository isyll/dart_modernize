import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Renames unused `__`, `___` parameters to `_`.
///
///     separatorBuilder: (_, __) => const Divider(),
///         ->  separatorBuilder: (_, _) => const Divider(),
///     errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
///         ->  errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
///     } catch (_, __) {   ->  } catch (_, _) {
///
/// Since Dart 3.7, `_` declares nothing and can repeat, so the extra
/// underscores written to dodge the old duplicate-name error are noise; this is
/// what the lint `unnecessary_underscores` asks for. Only positional
/// parameters of a function, method, constructor or closure, and the variables
/// of a `catch` clause, and only when nothing reads them. A named parameter's
/// name is part of its function's API, so it stays.
final class WildcardParameters implements Transformation {
  const WildcardParameters({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'wildcard-parameters';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    if (!unit.libraryElement.featureSet.isEnabled(.wildcard_variables)) {
      return const [];
    }
    final visitor = _Visitor();
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _Visitor extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  static final _underscores = RegExp(r'^__+$');

  @override
  void visitCatchClause(CatchClause node) {
    for (final parameter in [
      ?node.exceptionParameter,
      ?node.stackTraceParameter,
    ]) {
      _rename(parameter.name, parameter.declaredFragment?.element, node.body);
    }
    super.visitCatchClause(node);
  }

  @override
  void visitRegularFormalParameter(RegularFormalParameter node) {
    final name = node.name;
    if (name != null && node.isPositional && node.functionTypedSuffix == null) {
      final owner = node.parent?.parent;
      final scope = switch (owner) {
        FunctionExpression() ||
        MethodDeclaration() ||
        ConstructorDeclaration() => owner,
        _ => null,
      };
      if (scope != null) {
        _rename(name, node.declaredFragment?.element, scope);
      }
    }
    super.visitRegularFormalParameter(node);
  }

  void _rename(Token name, Element? element, AstNode scope) {
    if (element == null || !_underscores.hasMatch(name.lexeme)) return;
    final finder = _ReferenceFinder(element);
    scope.accept(finder);
    if (finder.found) return;
    edits.add(.new(offset: name.offset, length: name.length, replacement: '_'));
  }
}

/// Looks for a read of [target].
class _ReferenceFinder(final Element target) extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == target) found = true;
    super.visitSimpleIdentifier(node);
  }
}

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

/// Returns the resolved element when [expr] is a side-effect-free *stable
/// reference* (a bare local variable or formal parameter), and `null`
/// otherwise.
///
/// The null-aware passes collapse a guarded expression such as
/// `if (x != null) ...x` into a form that evaluates it **once** instead of
/// twice (the test and the use). That is only safe when the expression has no
/// side effects and yields the same value on each read, which a plain local or
/// parameter reference guarantees. Getters, method calls, and indexed accesses
/// might run code or observe a changed value between reads, so they are
/// rejected.
Element? stableReference(Expression expr) {
  if (expr is! SimpleIdentifier) return null;
  final element = expr.element;
  if (element is LocalVariableElement || element is FormalParameterElement) {
    return element;
  }
  return null;
}

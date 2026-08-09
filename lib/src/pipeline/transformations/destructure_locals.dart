import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Collapses a local that exists only to read fields off it into a single
/// destructuring declaration.
///
/// Records:
///   final result = computePair();      ->  final (a, b) = computePair();
///   final a = result.$1;
///   final b = result.$2;
///
/// Objects:
///   final p = getPoint();              ->  final Point(:x, :y) = getPoint();
///   final x = p.x;
///   final y = p.y;
///
/// Binding names come from the locals that already exist, so nothing is
/// invented. A local whose name differs from the field keeps its own name
/// (`final x = p.first` becomes `Point(first: x)`).
///
/// The rewrite is applied only when ALL of the following hold:
///   * the intermediate local is declared with an initializer and immediately
///     followed by a contiguous run of declarations that each read one field off
///     it, with nothing else in between;
///   * the intermediate is used nowhere else at all, so removing it is safe: not
///     read on its own, not reassigned, not captured, not passed whole;
///   * each field read resolves to a **final, non-late instance field** (for an
///     object) or a positional record field. Destructuring reads every field
///     once, up front, where the original read each one where it was declared,
///     so an arbitrary getter that runs code, or a `late final` whose
///     initializer would be forced early, is left alone;
///   * none of the run's statements carries a comment, which the single
///     replacement span would otherwise drop; and
///   * for an object, the static type is a class with a usable name.
///
/// Records with named fields are skipped: mixing `(:a, b: c)` bindings with
/// positional arity is easy to get subtly wrong, and the positional form already
/// covers the shape this pass is aimed at.
final class DestructureLocals implements Transformation {
  const DestructureLocals({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'destructure-locals';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _DestructureLocalsVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _DestructureLocalsVisitor extends RecursiveAstVisitor<void> {
  _DestructureLocalsVisitor(this.source);
  final String source;

  final edits = <SourceEdit>[];

  @override
  void visitBlock(Block node) {
    super.visitBlock(node);
    final statements = node.statements;
    for (var i = 0; i < statements.length; i++) {
      _collectAt(statements, i);
    }
  }

  void _collectAt(NodeList<Statement> statements, int index) {
    final intermediate = _singleDeclaration(statements[index]);
    if (intermediate == null) return;
    final initializer = intermediate.declaration.initializer;
    if (initializer == null) return;

    final target = intermediate.declaration.declaredFragment?.element;
    if (target == null) return;

    // Collect the contiguous run of `final name = target.field;` declarations.
    final reads = <_FieldBinding>[];
    var end = index;
    for (var i = index + 1; i < statements.length; i++) {
      final binding = _fieldBinding(statements[i], target);
      if (binding == null) break;
      if (statements[i].beginToken.precedingComments != null) return;
      reads.add(binding);
      end = i;
    }
    if (reads.isEmpty) return;

    // The intermediate must vanish, so every remaining mention disqualifies it.
    final body = _enclosingFunctionBody(statements[index]);
    if (body == null) return;
    final counter = _ReferenceCounter(target);
    body.accept(counter);
    if (counter.count != reads.length) return;

    final pattern = _pattern(intermediate.declaration, reads);
    if (pattern == null) return;

    // `var` only when a binding is later reassigned, so `final` stays the norm.
    final keyword = reads.any((r) => !r.isFinal) ? 'var' : 'final';
    final initializerSource = source.substring(
      initializer.offset,
      initializer.end,
    );

    edits.add(
      .new(
        offset: statements[index].offset,
        length: statements[end].end - statements[index].offset,
        replacement: '$keyword $pattern = $initializerSource;',
      ),
    );
  }

  /// Renders the pattern for the intermediate's type, or null when unsupported.
  String? _pattern(VariableDeclaration declaration, List<_FieldBinding> reads) {
    final type = declaration.declaredFragment?.element.type;
    if (type is RecordType) return _recordPattern(type, reads);
    if (type is InterfaceType) {
      final name = type.element.name;
      if (name == null || name.isEmpty) return null;
      final fields = reads.map((r) => r.binding).join(', ');
      return '$name($fields)';
    }
    return null;
  }

  /// A positional record pattern, with `_` standing in for fields never read.
  ///
  /// Positional patterns must match the record's arity, so the unread slots
  /// cannot simply be dropped the way an object pattern's can.
  String? _recordPattern(RecordType type, List<_FieldBinding> reads) {
    if (type.namedFields.isNotEmpty) return null;

    final byPosition = <int, String>{};
    for (final read in reads) {
      final position = _positionalIndex(read.field);
      if (position == null || position > type.positionalFields.length) {
        return null;
      }
      if (byPosition.containsKey(position)) return null;
      byPosition[position] = read.name;
    }

    final slots = [
      for (var i = 1; i <= type.positionalFields.length; i++)
        byPosition[i] ?? '_',
    ];
    return '(${slots.join(', ')})';
  }

  /// Parses `$1` into 1; returns null for anything else.
  int? _positionalIndex(String field) {
    if (!field.startsWith(r'$')) return null;
    return int.tryParse(field.substring(1));
  }

  /// Returns the single-variable declaration [statement] holds, or null.
  _SingleDeclaration? _singleDeclaration(Statement statement) {
    if (statement is! VariableDeclarationStatement) return null;
    final variables = statement.variables;
    if (variables.variables.length != 1) return null;
    if (variables.keyword == null) return null;
    if (variables.type != null) return null;
    return .new(
      declaration: variables.variables.single,
      isFinal: variables.isFinal,
    );
  }

  /// Returns the binding [statement] declares when it is exactly
  /// `final name = target.field;`, and null otherwise.
  _FieldBinding? _fieldBinding(Statement statement, Element target) {
    final single = _singleDeclaration(statement);
    if (single == null) return null;

    // `p.x` is a PrefixedIdentifier, but a record read like `pair.$1` comes
    // through as a PropertyAccess, so both shapes have to be unwrapped.
    final initializer = single.declaration.initializer;
    final (
      SimpleIdentifier? receiver,
      SimpleIdentifier? property,
    ) = switch (initializer) {
      PrefixedIdentifier(:final prefix, :final identifier) => (
        prefix,
        identifier,
      ),
      PropertyAccess(:final target, :final propertyName)
          when target is SimpleIdentifier =>
        (target, propertyName),
      _ => (null, null),
    };
    if (receiver == null || property == null) return null;
    if (receiver.element != target) return null;

    // A record field is immutable and side-effect free by construction, so it
    // needs no element check; its access does not resolve to a FieldElement.
    final isRecordField = receiver.staticType is RecordType;
    if (!isRecordField && !_isFinalInstanceField(property.element)) return null;

    return .new(
      name: single.declaration.name.lexeme,
      field: property.name,
      isFinal: single.isFinal,
    );
  }

  /// True for a final, non-late instance field, the only member kind whose read
  /// position is safe to move.
  bool _isFinalInstanceField(Element? element) {
    final field = switch (element) {
      FieldElement() => element,
      GetterElement(:final variable) =>
        variable is FieldElement ? variable : null,
      _ => null,
    };
    if (field == null) return false;
    return field.isFinal && !field.isStatic && !field.isLate;
  }

  AstNode? _enclosingFunctionBody(AstNode node) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is FunctionBody) return n;
    }
    return null;
  }
}

/// One `final name = intermediate.field;` declaration.
final class _FieldBinding {
  const _FieldBinding({
    required this.name,
    required this.field,
    required this.isFinal,
  });

  /// The local being declared, e.g. `x`.
  final String name;

  /// The field being read off the intermediate, e.g. `x` or `$1`.
  final String field;

  /// Whether the declaration used `final`.
  final bool isFinal;

  /// The object-pattern binding: `:x` when the names match, else `first: x`.
  String get binding => name == field ? ':$name' : '$field: $name';
}

final class _SingleDeclaration {
  const _SingleDeclaration({required this.declaration, required this.isFinal});
  final VariableDeclaration declaration;
  final bool isFinal;
}

/// Counts references to the intermediate local across the whole function.
class _ReferenceCounter extends RecursiveAstVisitor<void> {
  _ReferenceCounter(this.target);
  final Element target;

  int count = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (node.element != target) return;
    // The declaration's own name is not a reference.
    if (node.parent is VariableDeclaration) return;
    count++;
  }
}

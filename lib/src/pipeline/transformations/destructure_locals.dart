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
/// The names come from the locals that already exist. One named differently
/// from its field keeps its own name, so `final x = p.first` gives
/// `Point(first: x)`.
///
/// Skipped when:
///   * the field reads are not one unbroken run right after the declaration;
///   * the intermediate is used anywhere else, since it disappears;
///   * a field is not a final, non-late instance field, or a positional record
///     field. All the reads move up to the declaration, so a computed getter
///     could end up running earlier than it did;
///   * a statement in the run carries a comment, which the rewrite would drop;
///   * the type has no usable name;
///   * the record has named fields. Only the positional form is handled.
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

    // The intermediate is removed, so it must have no other use.
    final body = _enclosingFunctionBody(statements[index]);
    if (body == null) return;
    final counter = _ReferenceCounter(target);
    body.accept(counter);
    if (counter.count != reads.length) return;

    final pattern = _pattern(intermediate.declaration, reads);
    if (pattern == null) return;

    // `var` only if one of the bindings was not final.
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

  /// A positional record pattern, using `_` for fields the code never reads.
  ///
  /// A positional pattern has to list every field, so unread ones need a slot.
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

    // `p.x` parses as a PrefixedIdentifier, `pair.$1` as a PropertyAccess.
    final initializer = single.declaration.initializer;
    SimpleIdentifier? receiver;
    SimpleIdentifier? property;
    if (initializer is PrefixedIdentifier) {
      receiver = initializer.prefix;
      property = initializer.identifier;
    } else if (initializer is PropertyAccess) {
      final accessTarget = initializer.target;
      if (accessTarget is SimpleIdentifier) {
        receiver = accessTarget;
        property = initializer.propertyName;
      }
    }
    if (receiver == null || property == null) return null;
    if (receiver.element != target) return null;

    // A record field is always immutable, and does not resolve to a
    // FieldElement, so it skips the check below.
    final isRecordField = receiver.staticType is RecordType;
    if (!isRecordField && !_isFinalInstanceField(property.element)) return null;

    return .new(
      name: single.declaration.name.lexeme,
      field: property.name,
      isFinal: single.isFinal,
    );
  }

  /// True for a final, non-late instance field, the only kind safe to move.
  bool _isFinalInstanceField(Element? element) {
    FieldElement? field;
    if (element is FieldElement) {
      field = element;
    } else if (element is GetterElement) {
      final variable = element.variable;
      if (variable is FieldElement) field = variable;
    }
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

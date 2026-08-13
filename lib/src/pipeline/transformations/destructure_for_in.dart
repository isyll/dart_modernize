import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Moves a for-in loop variable's field reads into an object pattern in the
/// loop header.
///
/// Before:
///   for (final entry in map.entries) {
///     print('${entry.key} = ${entry.value}');
///   }
///
/// After:
///   for (final MapEntry(:key, :value) in map.entries) {
///     print('$key = $value');
///   }
///
/// Only the fields the body reads are moved, and each binding keeps the field's
/// own name.
///
/// Skipped when:
///   * the loop variable has an explicit type, so the header is not one span;
///   * the body does anything with the variable other than read a field off it;
///   * a field is not a final, non-late instance field. The pattern reads every
///     field once per iteration, where the body read them where they appeared,
///     so a computed getter could end up running when it did not before;
///   * a bound name is already used somewhere in the enclosing function;
///   * the element is a record, since `pair.$1` has no name to bind.
final class DestructureForIn implements Transformation {
  const DestructureForIn({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'destructure-for-in';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    final visitor = _DestructureForInVisitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _DestructureForInVisitor extends RecursiveAstVisitor<void> {
  _DestructureForInVisitor(this.source);
  final String source;

  final edits = <SourceEdit>[];

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    super.visitForEachPartsWithDeclaration(node);
    _collect(node);
  }

  void _collect(ForEachPartsWithDeclaration node) {
    final loopVariable = node.loopVariable;
    // An explicit type would have to be carried into the pattern; a bare
    // `final x` / `var x` keeps the replacement a single span.
    if (loopVariable.type != null) return;
    if (loopVariable.keyword == null) return;

    final element = loopVariable.declaredFragment?.element;
    if (element == null) return;

    final type = loopVariable.declaredFragment?.element.type;
    if (type is! InterfaceType) return;
    final typeName = type.element.name;
    if (typeName == null || typeName.isEmpty) return;

    final scope = node.parent;
    final uses = _FieldReadCollector(element);
    scope.accept(uses);
    if (!uses.allReadsAreFields || uses.reads.isEmpty) return;

    // Preserve first-read order so the pattern lists fields the way the body
    // uses them, which reads better than sorting.
    final fields = <String>[];
    for (final read in uses.reads) {
      final name = read.identifier.name;
      if (!_isDestructurableField(read.identifier.element)) return;
      if (!fields.contains(name)) fields.add(name);
    }

    final body = _enclosingFunctionBody(node);
    if (body == null) return;
    if (_collides(body, fields, uses.reads)) return;

    edits.add(
      .new(
        offset: loopVariable.offset,
        length: loopVariable.end - loopVariable.offset,
        replacement: 'final $typeName(${fields.map((f) => ':$f').join(', ')})',
      ),
    );
    for (final read in uses.reads) {
      edits.add(_readEdit(read));
    }
  }

  /// Replaces one `entry.key` read with the bare name `key`.
  ///
  /// Inside a string, `'${entry.key}'` becomes `'$key'`: the braces are no
  /// longer needed. They stay when the next character would run into the name,
  /// as in `'${entry.key}s'`.
  SourceEdit _readEdit(_FieldRead read) {
    final name = read.identifier.name;
    final interpolation = read.parent;
    if (interpolation is InterpolationExpression &&
        identical(interpolation.expression, read) &&
        interpolation.leftBracket.lexeme == r'${' &&
        !_continuesIdentifier(interpolation.end)) {
      return .new(
        offset: interpolation.offset,
        length: interpolation.end - interpolation.offset,
        replacement: '\$$name',
      );
    }
    return .new(
      offset: read.offset,
      length: read.end - read.offset,
      replacement: name,
    );
  }

  /// True when the character at [offset] could extend an identifier.
  bool _continuesIdentifier(int offset) {
    if (offset >= source.length) return false;
    final code = source.codeUnitAt(offset);
    const underscore = 0x5f;
    const dollar = 0x24;
    return code == underscore ||
        code == dollar ||
        (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5a) ||
        (code >= 0x61 && code <= 0x7a);
  }

  /// True for a final, non-late instance field, the only kind we can safely
  /// read at a different point.
  bool _isDestructurableField(Element? element) {
    final field = switch (element) {
      FieldElement() => element,
      GetterElement(:final variable) =>
        variable is FieldElement ? variable : null,
      _ => null,
    };
    if (field == null) return false;
    return field.isFinal && !field.isStatic && !field.isLate;
  }

  /// True when one of [fields] is already used as a name in [body].
  ///
  /// The property names we are about to remove do not count. The check is broad
  /// on purpose; at worst it leaves a loop alone.
  bool _collides(AstNode body, List<String> fields, List<_FieldRead> reads) {
    final replaced = {for (final read in reads) read.identifier};
    final finder = _NameFinder(fields.toSet(), replaced);
    body.accept(finder);
    return finder.found;
  }

  AstNode? _enclosingFunctionBody(AstNode node) {
    for (var n = node.parent; n != null; n = n.parent) {
      if (n is FunctionBody) return n;
    }
    return null;
  }
}

/// One `receiver.field` read of the loop variable.
typedef _FieldRead = PrefixedIdentifier;

/// Collects the loop variable's field reads and reports any other use.
class _FieldReadCollector extends RecursiveAstVisitor<void> {
  _FieldReadCollector(this.target);
  final Element target;

  final reads = <_FieldRead>[];

  /// False as soon as the variable is used as anything but a field receiver.
  bool allReadsAreFields = true;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (node.element != target) return;

    final parent = node.parent;
    // The declaration itself is not a use.
    if (parent is DeclaredIdentifier) return;
    // `entry.key`, with `entry` as the receiver rather than the field name.
    if (parent is PrefixedIdentifier && identical(parent.prefix, node)) {
      reads.add(parent);
      return;
    }
    allReadsAreFields = false;
  }
}

/// Looks for identifiers that would clash with a new pattern binding.
class _NameFinder extends RecursiveAstVisitor<void> {
  _NameFinder(this.names, this.ignored);
  final Set<String> names;
  final Set<SimpleIdentifier> ignored;

  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    super.visitSimpleIdentifier(node);
    if (ignored.contains(node)) return;
    if (names.contains(node.name)) found = true;
  }
}

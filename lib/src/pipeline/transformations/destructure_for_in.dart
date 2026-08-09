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
/// Only the fields actually read are destructured, and the binding always takes
/// the field's own name, so no identifier is ever invented.
///
/// The rewrite is applied only when ALL of the following hold:
///   * the loop variable is declared with a bare `var`/`final` and no explicit
///     type, so the header is a single clean span to replace;
///   * every reference to it in the loop is the receiver of a field read
///     (`entry.key`); using it whole, reassigning it, or calling a method on it
///     all disqualify the loop;
///   * every field read resolves to a **final, non-late instance field** of the
///     loop variable's own class. This is the load-bearing guard: destructuring
///     reads each field exactly once per iteration, where the original read it
///     once per use and only along the paths it actually took. For a plain final
///     field that is unobservable, but an arbitrary getter could run code, and a
///     `late final` field could have its initializer forced on an iteration that
///     never used it;
///   * the loop variable's static type is a class with a usable name, which
///     becomes the pattern's type; and
///   * no field name collides with another name used anywhere in the enclosing
///     function, since the binding introduces that bare name into the loop.
///
/// Records are left alone. A positional field (`pair.$1`) has no name to bind,
/// and inventing one is exactly what this pass refuses to do.
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

  /// Replaces one `entry.key` read with the bare binding `key`.
  ///
  /// `'${entry.key}'` would otherwise become `'${key}'`, whose braces are now
  /// pointless (and which `unnecessary_brace_in_string_interps` flags), so the
  /// whole interpolation collapses to `'$key'` instead. The braces are kept when
  /// the next character would run into the name, as in `'${entry.key}s'`, where
  /// dropping them would read as a different identifier.
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

  /// True when [element] is a final, non-late instance field, the only member
  /// kind whose read count is safe to change.
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

  /// True when binding any of [fields] as a bare name would shadow or clash
  /// with an identifier already used in [body].
  ///
  /// Every identifier in the enclosing function counts, except the property
  /// names of the reads being replaced (those disappear with the rewrite). This
  /// is deliberately blunt: a false positive only means a loop is left alone.
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

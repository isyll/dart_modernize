import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Declares constructors without repeating the class name (Dart 3.13).
///
///     Point(this.x, this.y);              ->  new(this.x, this.y);
///     const Point.origin() : x = 0 ...;   ->  const new origin() : x = 0 ...;
///     factory Point.fromJson(...) => ...  ->  factory fromJson(...) => ...
///     factory Point(int x) => ...         ->  factory(int x) => ...
///
/// Calls do not change: `Point.origin()` and `Point.fromJson(...)` are written
/// as before. In an enum, the redundant `const` of a generative constructor
/// goes too, since enum constructors are always constant. Applies in classes,
/// mixin classes, enums, and extension types; this is what the lints
/// `unnecessary_type_name_in_constructor` and
/// `unnecessary_const_in_enum_constructor` ask for.
///
/// A header with a comment between the class name and the parameter list is
/// left alone, since the rewrite would drop it.
final class ConstructorShorthands implements Transformation {
  const ConstructorShorthands({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'constructor-shorthands';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    if (!unit.libraryElement.featureSet.isEnabled(.primary_constructors)) {
      return const [];
    }
    final visitor = _Visitor(unit.content);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _Visitor(final String source) extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _collect(node);
    super.visitConstructorDeclaration(node);
  }

  void _collect(ConstructorDeclaration node) {
    // The class name before the constructor name marks the old form; the new
    // form has `new` or `factory` in its place.
    final typeName = node.typeName?.token;
    if (typeName == null) return;
    final name = node.name;
    final end = (name ?? typeName).end;
    final constructorName = name == null || name.lexeme == 'new'
        ? null
        : name.lexeme;

    final factory = node.factoryKeyword;
    // `factory C(` becomes `factory(`, so the space after `factory` goes too.
    final start = factory != null && constructorName == null
        ? factory.end
        : typeName.offset;
    if (_hasComment(start, end)) return;
    edits.add(
      .new(
        offset: start,
        length: end - start,
        replacement: switch ((factory, constructorName)) {
          (null, null) => 'new',
          (null, final named?) => 'new $named',
          (_, null) => '',
          (_, final named?) => named,
        },
      ),
    );
    if (factory != null) return;

    final constKeyword = node.constKeyword;
    if (constKeyword != null && node.parent?.parent is EnumDeclaration) {
      edits.add(
        .new(
          offset: constKeyword.offset,
          length: typeName.offset - constKeyword.offset,
          replacement: '',
        ),
      );
    }
  }

  /// Whether the text from [start] to [end], which only holds the class
  /// name, a period, and a constructor name otherwise, has a comment in it.
  bool _hasComment(int start, int end) {
    final text = source.substring(start, end);
    return text.contains('//') || text.contains('/*');
  }
}

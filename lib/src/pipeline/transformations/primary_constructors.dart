import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Promotes eligible single-constructor classes to primary constructor form.
///
/// Primary constructors are stable in Dart 3.13, which is also this tool's SDK
/// floor. The feature check in [editsFor] is a second guard, for a library
/// pinned to an older language version.
///
/// A class is eligible when:
///   * it is not abstract;
///   * it is not directly extended by another class in the same compilation
///     unit (conservative: avoids touching the superclass while leaving a
///     subclass with an initializer-list super call);
///   * it has exactly one unnamed, non-factory generative constructor with an
///     empty body and no initializer list;
///   * every formal parameter is a `this.field` initializing formal;
///   * every field declaration names a single variable with an explicit type.
///
/// Fields that the constructor does not initialise stay in the class body.
/// Consumed fields move into the header: `final` fields become `final T name`,
/// mutable fields become `var T name`.
///
/// A `const` constructor becomes `class const Point(final int x)`, with the
/// modifier between `class` and the name. Dart already requires every field of
/// a const class to be final, so the header never needs `var`.
///
/// Named primary constructors (`class Point.origin(...)`) are not produced.
final class PrimaryConstructors implements Transformation {
  const PrimaryConstructors({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'primary-constructors';

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

  /// Names of classes that appear in an `extends` clause within this file.
  final _extendedNames = <String>{};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _tryRewrite(node);
    super.visitClassDeclaration(node);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    for (final decl in node.declarations) {
      if (decl is ClassDeclaration) {
        final superName = decl.extendsClause?.superclass.name.lexeme;
        if (superName != null) _extendedNames.add(superName);
      }
    }
    super.visitCompilationUnit(node);
  }

  String _leadingIndent(int offset) {
    var pos = offset - 1;
    while (pos >= 0 && source[pos] != '\n') {
      pos--;
    }
    final lineStart = pos + 1;
    final buf = StringBuffer();
    for (var i = lineStart; i < offset; i++) {
      final ch = source[i];
      if (ch == ' ' || ch == '\t') {
        buf.write(ch);
      } else {
        break;
      }
    }
    return buf.toString();
  }

  /// Where a retained member starts, counting any `//` comment above it.
  ///
  /// A doc comment is already part of the member, but a plain comment is not,
  /// so copying from `member.offset` would leave it behind.
  int _startIncludingComments(ClassMember member) =>
      member.beginToken.precedingComments?.offset ?? member.offset;

  /// True when the source has a blank line just before [offset].
  ///
  /// Used to keep the spacing the class was written with; without it every
  /// retained member ends up on consecutive lines.
  bool _blankLineBefore(int offset) {
    var newlines = 0;
    for (var i = offset - 1; i >= 0; i--) {
      final ch = source[i];
      if (ch == '\n') {
        newlines++;
        if (newlines >= 2) return true;
      } else if (ch != ' ' && ch != '\t' && ch != '\r') {
        return false;
      }
    }
    return false;
  }

  /// True when [field] has a doc comment, a plain comment, or an annotation.
  ///
  /// A promoted field keeps only its type and name, so any of those would be
  /// thrown away. Running the tool over its own sources is what surfaced it:
  /// the promotion deleted 54 lines of documentation in one go.
  bool _carriesAttachedText(FieldDeclaration field) =>
      field.documentationComment != null ||
      field.metadata.isNotEmpty ||
      field.beginToken.precedingComments != null;

  void _tryRewrite(ClassDeclaration cls) {
    // Already a primary constructor class: skip (idempotence).
    if (cls.namePart is PrimaryConstructorDeclaration) return;

    if (cls.abstractKeyword != null) return;

    // Don't rewrite a class that is directly extended in this file.
    if (_extendedNames.contains(cls.namePart.typeName.lexeme)) return;

    final members = cls.body.members;

    // Exactly one non-factory, non-redirecting generative constructor.
    final ctors = members.whereType<ConstructorDeclaration>().toList();
    final generative = ctors
        .where(
          (c) =>
              c.factoryKeyword == null &&
              !c.initializers.any((i) => i is RedirectingConstructorInvocation),
        )
        .toList();
    if (generative.length != 1) return;

    final ctor = generative.first;
    if (ctor.name != null) return;
    if (ctor.body is! EmptyFunctionBody) return;
    if (ctor.initializers.isNotEmpty) return;
    if (ctor.externalKeyword != null) return;
    final isConst = ctor.constKeyword != null;

    final params = ctor.parameters.parameters;
    if (!params.every((p) => p is FieldFormalParameter)) return;

    // All field declarations must name a single variable.
    final fieldDecls = members.whereType<FieldDeclaration>().toList();
    for (final fd in fieldDecls) {
      if (fd.fields.variables.length != 1) return;
    }

    // Map non-static field names to their declarations.
    final fieldByName = <String, FieldDeclaration>{
      for (final fd in fieldDecls)
        if (!fd.isStatic) fd.fields.variables.single.name.lexeme: fd,
    };

    // Params must be all positional or all named (no mixed).
    final typedParams = params.cast<FieldFormalParameter>();
    final hasNamed = typedParams.any((p) => p.isNamed);
    final allNamed = typedParams.every((p) => p.isNamed);
    if (hasNamed && !allNamed) return;

    final primaryParams = <String>[];
    final consumedNames = <String>{};

    for (final param in typedParams) {
      final fieldName = param.name.lexeme;
      final fd = fieldByName[fieldName];
      if (fd == null) return;
      final typeAnnotation = fd.fields.type;
      if (typeAnnotation == null) return;

      // Only the type and the name make it into the header, so anything else
      // attached to the field would be thrown away. Leave the class alone
      // rather than delete a doc comment or an annotation.
      if (_carriesAttachedText(fd)) return;

      // A const class cannot have a mutable field, so this should not fire.
      // Kept because `class const C(var int x)` would not compile.
      if (isConst && !fd.fields.isFinal) return;

      final modifier = fd.fields.isFinal ? 'final' : 'var';
      final typeText = source.substring(
        typeAnnotation.offset,
        typeAnnotation.end,
      );
      final requiredPrefix = param.isRequiredNamed ? 'required ' : '';
      primaryParams.add('$requiredPrefix$modifier $typeText $fieldName');
      consumedNames.add(fieldName);
    }

    // Everything stays except the constructor being promoted and the fields it
    // takes over. Only that one constructor moves into the header: a factory or
    // a redirecting constructor is part of the class's API and has to survive.
    final retained = <ClassMember>[];
    for (final member in members) {
      if (identical(member, ctor)) continue;
      if (member is FieldDeclaration &&
          !member.isStatic &&
          consumedNames.contains(member.fields.variables.single.name.lexeme)) {
        continue;
      }
      retained.add(member);
    }

    final classIndent = _leadingIndent(cls.offset);

    final paramsText = hasNamed
        ? '{${primaryParams.join(', ')}}'
        : primaryParams.join(', ');

    final classModifiers = cls.offset < cls.classKeyword.offset
        ? source.substring(cls.offset, cls.classKeyword.offset)
        : '';

    final typeParamsText = cls.namePart.typeParameters != null
        ? source.substring(
            cls.namePart.typeParameters!.offset,
            cls.namePart.typeParameters!.end,
          )
        : '';

    final extendsText = cls.extendsClause != null
        ? ' ${source.substring(cls.extendsClause!.offset, cls.extendsClause!.end)}'
        : '';
    final withText = cls.withClause != null
        ? ' ${source.substring(cls.withClause!.offset, cls.withClause!.end)}'
        : '';
    final implementsText = cls.implementsClause != null
        ? ' ${source.substring(cls.implementsClause!.offset, cls.implementsClause!.end)}'
        : '';

    final String body;
    if (retained.isEmpty) {
      body = ';';
    } else {
      final memberIndent = '$classIndent  ';
      final lines = <String>[];
      for (var i = 0; i < retained.length; i++) {
        final member = retained[i];
        final start = _startIncludingComments(member);
        if (i > 0 && _blankLineBefore(start)) lines.add('');
        lines.add('$memberIndent${source.substring(start, member.end)}');
      }
      body = ' {\n${lines.join('\n')}\n$classIndent}';
    }

    edits.add(
      .new(
        offset: cls.offset,
        length: cls.end - cls.offset,
        replacement:
            '${classModifiers}class ${isConst ? 'const ' : ''}'
            '${cls.namePart.typeName.lexeme}'
            '$typeParamsText($paramsText)$extendsText$withText$implementsText$body',
      ),
    );
  }
}

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Promotes eligible single-constructor classes to primary constructor form.
///
/// Primary constructors are stable as of Dart 3.13, which is also this tool's
/// SDK floor, so the syntax below is always available to a project the validator
/// let through. The feature-set check is kept as a second line of defence: it
/// reads the resolved language version rather than the SDK constraint, so an
/// individual library pinned lower still gets left alone instead of being handed
/// code it cannot compile.
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
/// A `const` constructor promotes to a constant primary constructor, where the
/// modifier sits between `class` and the name: `class const Point(final int x)`.
/// That is safe by construction. Dart already requires every instance field of a
/// const-constructor class to be final, so the header can never need `var`, and
/// the fields left in the body are copied over byte for byte, keeping whatever
/// made them constant. The guard below re-checks the finality anyway rather than
/// trusting that reasoning.
///
/// A *named* primary constructor (`class Point.origin(final int x)`) is valid
/// 3.13 syntax but is not produced here: the eligibility rule above admits only
/// an unnamed constructor.
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

class _Visitor extends RecursiveAstVisitor<void> {
  _Visitor(this.source);
  final String source;

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

      // A const-constructor class cannot hold a mutable instance field, so this
      // never fires on code that compiles. It is kept as a hard stop: emitting
      // `class const C(var int x)` would be a compile error, not a style slip.
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

    // Retained members: non-consumed fields and any other class members.
    final retained = <ClassMember>[];
    for (final member in members) {
      if (member is ConstructorDeclaration) continue;
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
      final memberTexts = retained
          .map((m) => '$memberIndent${source.substring(m.offset, m.end)}')
          .join('\n');
      body = ' {\n$memberTexts\n$classIndent}';
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

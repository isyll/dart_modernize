import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Promotes a class or an enum with one generative constructor to primary
/// constructor form.
///
///     class Config {                     class Config({
///       final String host;                 required final String host,
///       final int port;            ->      final int port = 8080,
///       Config({required this.host,      });
///           this.port = 8080});
///     }
///
/// Primary constructors are stable in Dart 3.13, which is also this tool's SDK
/// floor. The feature check in [editsFor] is a second guard, for a library
/// pinned to an older language version.
///
/// The constructor may be unnamed, named, or private (`class Vec._(...)`), and
/// may be `const`. Its parameters keep their kind, order, default values, and
/// `required`: positional, optional positional in `[...]`, named in `{...}`.
/// Each `this.field` parameter becomes a declaring parameter (`final T field`,
/// or `var T field` for a mutable field) and the field leaves the body; one
/// variable of a `final int x, y;` declaration can go while the other stays.
/// A plain parameter stays a plain parameter. From the initializer list,
/// `assert`s move to the primary constructor's body (`this : assert(...);`)
/// and a field initializer moves onto its field (`final int _v = raw * 2;`).
/// Factories and redirecting constructors stay in the body.
///
/// A class or enum is left alone when:
///   * it is abstract, a mixin class, or extended by another class in the
///     same file;
///   * the constructor has a body, a `super(...)` or redirecting initializer,
///     is external, or carries a doc comment, an annotation, or any comment,
///     which the header has nowhere to put;
///   * a parameter is annotated, covariant, function-typed, or a `this.x`
///     with its own type; or is `super.x`, unless the `super-parameters`
///     setting is on (it promotes every Flutter widget, a large diff);
///   * a promoted field is late, covariant, external, already initialized,
///     has no type, or carries a doc comment, an annotation, or a comment;
///   * the class is not `const`, is (or extends) an `@immutable` class, and
///     would keep a field with an initializer or a late field in its body.
///     The `prefer_const_constructors_in_immutables` lint of Dart 3.13 then
///     wrongly asks for `const` on the primary constructor, and `dart fix`
///     adds one that does not compile.
final class PrimaryConstructors implements Transformation {
  const PrimaryConstructors({
    required this.enabled,
    this.superParameters = false,
  });

  @override
  final bool enabled;

  /// Whether a constructor with `super.` parameters is promoted too.
  final bool superParameters;

  @override
  String get name => 'primary-constructors';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    if (!unit.libraryElement.featureSet.isEnabled(.primary_constructors)) {
      return const [];
    }
    final visitor = _Visitor(unit.content, superParameters: superParameters);
    unit.unit.accept(visitor);
    return visitor.edits;
  }
}

class _Visitor(final String source, {required final bool superParameters})
    extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  /// Names of classes that appear in an `extends` clause within this file.
  final _extendedNames = <String>{};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _tryClass(node);
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

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _tryEnum(node);
    super.visitEnumDeclaration(node);
  }

  /// Works out the promotion of the class or enum whose body holds [members],
  /// or returns null when it does not qualify.
  _Promotion? _analyze(List<ClassMember> members, {required bool isEnum}) {
    final ctors = members.whereType<ConstructorDeclaration>().toList();
    final generative = [
      for (final c in ctors)
        if (c.factoryKeyword == null &&
            !c.initializers.any((i) => i is RedirectingConstructorInvocation))
          c,
    ];
    if (generative.length != 1) return null;
    final ctor = generative.single;

    if (ctor.externalKeyword != null) return null;
    if (ctor.documentationComment != null || ctor.metadata.isNotEmpty) {
      return null;
    }
    if (_hasComment(ctor)) return null;
    final body = ctor.body;
    if (body is BlockFunctionBody) {
      if (body.block.statements.isNotEmpty) return null;
    } else if (body is! EmptyFunctionBody) {
      return null;
    }
    final isConst = isEnum || ctor.constKeyword != null;

    final fields = <String, (FieldDeclaration, VariableDeclaration)>{
      for (final fd in members.whereType<FieldDeclaration>())
        if (!fd.isStatic)
          for (final v in fd.fields.variables) v.name.lexeme: (fd, v),
    };

    final positional = <String>[];
    final optional = <String>[];
    final named = <String>[];
    final consumed = <VariableDeclaration>{};
    for (final param in ctor.parameters.parameters) {
      if (param.metadata.isNotEmpty || param.covariantKeyword != null) {
        return null;
      }
      final String text;
      if (param is FieldFormalParameter) {
        if (param.type != null || param.functionTypedSuffix != null) {
          return null;
        }
        final entry = fields[param.name.lexeme];
        if (entry == null) return null;
        final (fd, variable) = entry;
        if (!_isPromotable(fd, variable, isConst: isConst)) return null;
        consumed.add(variable);
        final type = fd.fields.type!;
        final modifier = fd.fields.isFinal ? 'final' : 'var';
        final defaultValue = param.defaultClause?.value;
        text = [
          if (param.isRequiredNamed) 'required ',
          '$modifier ${_text(type)} ${param.name.lexeme}',
          if (defaultValue != null) ' = ${_text(defaultValue)}',
        ].join();
      } else if (param is SuperFormalParameter) {
        if (!superParameters || isEnum) return null;
        text = _text(param);
      } else if (param is RegularFormalParameter) {
        if (param.name == null ||
            param.constFinalOrVarKeyword != null ||
            param.functionTypedSuffix != null) {
          return null;
        }
        text = _text(param);
      } else {
        return null;
      }
      if (param.isNamed) {
        named.add(text);
      } else if (param.isOptionalPositional) {
        optional.add(text);
      } else {
        positional.add(text);
      }
    }

    final asserts = <String>[];
    final moved = <VariableDeclaration, String>{};
    for (final initializer in ctor.initializers) {
      if (initializer is AssertInitializer) {
        asserts.add(_text(initializer));
      } else if (initializer is ConstructorFieldInitializer) {
        final entry = fields[initializer.fieldName.name];
        if (entry == null) return null;
        final (fd, variable) = entry;
        if (consumed.contains(variable) || moved.containsKey(variable)) {
          return null;
        }
        if (variable.initializer != null || fd.fields.isLate) return null;
        moved[variable] = _text(initializer.expression);
      } else {
        return null;
      }
    }

    return .new(
      ctor: ctor,
      isConst: isConst,
      parameters: [
        ...positional,
        if (optional.isNotEmpty) '[${optional.join(', ')}]',
        if (named.isNotEmpty) '{${named.join(', ')}}',
      ].join(', '),
      consumed: consumed,
      moved: moved,
      asserts: asserts,
    );
  }

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

  /// The body text after promotion: the retained members, led by the primary
  /// constructor's own body when it has asserts, or `;` when nothing is left.
  String _body(
    _Promotion promotion,
    List<ClassMember> members,
    String indent, {
    String? enumConstants,
  }) {
    final memberIndent = '$indent  ';
    final lines = <String>[];
    if (promotion.asserts.isNotEmpty) {
      lines.add('${memberIndent}this : ${promotion.asserts.join(', ')};');
    }
    for (final member in members) {
      if (identical(member, promotion.ctor)) continue;
      final text = _memberText(member, promotion);
      if (text == null) continue;
      final start = _startIncludingComments(member);
      if (lines.isNotEmpty &&
          (_blankLineBefore(start) ||
              lines.length == 1 && promotion.asserts.isNotEmpty)) {
        lines.add('');
      }
      lines.add('$memberIndent$text');
    }

    if (enumConstants != null) {
      if (lines.isEmpty) return ' {\n$memberIndent$enumConstants\n$indent}';
      final constants = enumConstants.endsWith(',')
          ? enumConstants.substring(0, enumConstants.length - 1)
          : enumConstants;
      return ' {\n$memberIndent$constants;\n\n${lines.join('\n')}\n$indent}';
    }
    if (lines.isEmpty) return ';';
    return ' {\n${lines.join('\n')}\n$indent}';
  }

  /// The `.name` part of the header for the promoted constructor, empty for an
  /// unnamed one (including `C.new`).
  String _constructorName(ConstructorDeclaration ctor) {
    final name = ctor.name?.lexeme;
    return name == null || name == 'new' ? '' : '.$name';
  }

  /// Whether [ctor] carries a comment: on its own line above it, between
  /// its tokens, or after it on its last line. A comment trailing the line
  /// above belongs to that line, not to the constructor.
  bool _hasComment(ConstructorDeclaration ctor) {
    var token = ctor.firstTokenAfterCommentAndMetadata;
    if (_ownLineCommentBefore(token) != null) return true;
    while (token != ctor.endToken) {
      final next = token.next;
      if (next == null) return false;
      token = next;
      if (token.precedingComments != null) return true;
    }
    return _trailingCommentEnd(ctor.endToken) != null;
  }

  /// The first comment before [token] that starts on its own line, or null.
  /// A comment on the same line as the code before it trails that code.
  Token? _ownLineCommentBefore(Token token) {
    final previous = token.previous;
    var from = previous == null || previous.isEof ? 0 : previous.end;
    for (
      Token? comment = token.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      if (source.substring(from, comment.offset).contains('\n')) {
        return comment;
      }
      from = comment.end;
    }
    return null;
  }

  /// The end of the comment that follows [token] on the same line, or null.
  int? _trailingCommentEnd(Token token) {
    final comment = token.next?.precedingComments;
    if (comment == null) return null;
    if (source.substring(token.end, comment.offset).contains('\n')) {
      return null;
    }
    return comment.end;
  }

  /// Whether [variable] of [fd] can move into the header as a declaring
  /// parameter. A field with a doc comment, a comment, or an annotation keeps
  /// none of it in the header, so it stays a field. Running the tool over its
  /// own sources is what surfaced that: the promotion deleted 54 lines of
  /// documentation in one go.
  bool _isPromotable(
    FieldDeclaration fd,
    VariableDeclaration variable, {
    required bool isConst,
  }) {
    final list = fd.fields;
    if (list.type == null || list.isLate || list.isConst) return false;
    if (fd.covariantKeyword != null || fd.externalKeyword != null) return false;
    if (fd.abstractKeyword != null) return false;
    if (variable.initializer != null) return false;
    if (fd.documentationComment != null ||
        fd.metadata.isNotEmpty ||
        _ownLineCommentBefore(fd.beginToken) != null ||
        _trailingCommentEnd(fd.endToken) != null) {
      return false;
    }
    // `class const C(var int x)` would not compile; a const class has no
    // mutable fields anyway.
    return !isConst || list.isFinal;
  }

  /// Whether the class, or one of its supertypes, is annotated `@immutable`.
  bool _isImmutable(ClassDeclaration cls) {
    final element = cls.declaredFragment?.element;
    if (element == null) return false;
    if (element.metadata.hasImmutable) return true;
    return element.allSupertypes.any((t) => t.element.metadata.hasImmutable);
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

  /// The text of a retained [member], with promoted fields taken out of its
  /// declaration and moved initializers added, or null when nothing of it is
  /// left.
  String? _memberText(ClassMember member, _Promotion promotion) {
    final start = _startIncludingComments(member);
    final end = _endIncludingComment(member);
    if (member is! FieldDeclaration || member.isStatic) {
      return source.substring(start, end);
    }
    final variables = member.fields.variables;
    final kept = [
      for (final v in variables)
        if (!promotion.consumed.contains(v)) v,
    ];
    if (kept.isEmpty) return null;
    if (kept.length == variables.length &&
        !kept.any(promotion.moved.containsKey)) {
      return source.substring(start, end);
    }
    final prefix = source.substring(start, variables.first.offset);
    final rendered = [
      for (final v in kept)
        switch (promotion.moved[v]) {
          final value? => '${_text(v)} = $value',
          null => _text(v),
        },
    ];
    return '$prefix${rendered.join(', ')};${source.substring(member.end, end)}';
  }

  /// Where a retained member starts, counting any `//` comment on its own line
  /// above it.
  ///
  /// A doc comment is already part of the member, but a plain comment is not,
  /// so copying from `member.offset` would leave it behind. A comment trailing
  /// the line above belongs to the member before.
  int _startIncludingComments(ClassMember member) =>
      _ownLineCommentBefore(member.beginToken)?.offset ?? member.offset;

  /// Where a retained member ends, counting a comment after it on its line.
  int _endIncludingComment(ClassMember member) =>
      _trailingCommentEnd(member.endToken) ?? member.end;

  String _text(AstNode node) => source.substring(node.offset, node.end);

  void _tryClass(ClassDeclaration cls) {
    // Already a primary constructor class: skip (idempotence).
    if (cls.namePart is PrimaryConstructorDeclaration) return;
    if (cls.abstractKeyword != null || cls.mixinKeyword != null) return;

    // Don't rewrite a class that is directly extended in this file.
    if (_extendedNames.contains(cls.namePart.typeName.lexeme)) return;

    final body = cls.body;
    if (body is! BlockClassBody) return;
    final members = body.members;
    final promotion = _analyze(members, isEnum: false);
    if (promotion == null) return;

    if (!promotion.isConst && _isImmutable(cls)) {
      final keepsInitializedField =
          promotion.moved.isNotEmpty ||
          members.whereType<FieldDeclaration>().any(
            (fd) =>
                !fd.isStatic &&
                (fd.fields.isLate ||
                    fd.fields.variables.any(
                      (v) =>
                          v.initializer != null &&
                          !promotion.consumed.contains(v),
                    )),
          );
      if (keepsInitializedField) return;
    }

    final classModifiers = cls.offset < cls.classKeyword.offset
        ? source.substring(cls.offset, cls.classKeyword.offset)
        : '';
    final typeParameters = cls.namePart.typeParameters;
    final clauses = [
      ?cls.extendsClause,
      ?cls.withClause,
      ?cls.implementsClause,
    ].map((c) => ' ${_text(c)}').join();

    edits.add(
      .new(
        offset: cls.offset,
        length: cls.end - cls.offset,
        replacement:
            '${classModifiers}class ${promotion.isConst ? 'const ' : ''}'
            '${cls.namePart.typeName.lexeme}'
            '${typeParameters == null ? '' : _text(typeParameters)}'
            '${_constructorName(promotion.ctor)}(${promotion.parameters})'
            '$clauses'
            '${_body(promotion, members, _leadingIndent(cls.offset))}',
      ),
    );
  }

  void _tryEnum(EnumDeclaration node) {
    if (node.namePart is PrimaryConstructorDeclaration) return;
    final body = node.body;
    if (body is! BlockEnumBody || body.constants.isEmpty) return;
    final promotion = _analyze(body.members, isEnum: true);
    if (promotion == null) return;

    final constantsEnd = body.semicolon?.offset ?? body.rightBracket.offset;
    final constants = source
        .substring(body.constants.first.offset, constantsEnd)
        .trimRight();
    if (constants.contains('//') || constants.contains('/*')) return;

    final typeParameters = node.namePart.typeParameters;
    final clauses = [
      ?node.withClause,
      ?node.implementsClause,
    ].map((c) => ' ${_text(c)}').join();

    edits.add(
      .new(
        offset: node.enumKeyword.offset,
        length: node.end - node.enumKeyword.offset,
        replacement:
            'enum ${node.namePart.typeName.lexeme}'
            '${typeParameters == null ? '' : _text(typeParameters)}'
            '${_constructorName(promotion.ctor)}(${promotion.parameters})'
            '$clauses'
            '${_body(promotion, body.members, _leadingIndent(node.offset), enumConstants: constants)}',
      ),
    );
  }
}

/// How one class or enum is promoted.
final class const _Promotion({
  /// The generative constructor that moves into the header.
  required final ConstructorDeclaration ctor,

  /// Whether the primary constructor is `const` (always, for an enum).
  required final bool isConst,

  /// The header's parameter list text, without the parentheses.
  required final String parameters,

  /// Field variables that become declaring parameters.
  required final Set<VariableDeclaration> consumed,

  /// Field variables that take over an initializer-list entry, with its
  /// expression text.
  required final Map<VariableDeclaration, String> moved,

  /// The `assert(...)` initializers, which stay in `this : ...;`.
  required final List<String> asserts,
});

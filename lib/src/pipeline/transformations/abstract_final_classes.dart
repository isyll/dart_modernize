import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../analysis/lint_rules.dart';
import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Adds `abstract final` to classes that expose only static members and are
/// never instantiated, extended, implemented, or mixed in anywhere within the
/// analyzed project.
///
/// Before:
///   class Constants { static const pi = 3.14; }
///
/// After:
///   abstract final class Constants { static const pi = 3.14; }
///
/// If the class has a single private unnamed constructor `ClassName._()` used
/// solely to prevent instantiation, that constructor is removed because
/// `abstract final` already prevents external instantiation. It stays when the
/// project enables `avoid_classes_with_only_static_members`, which that
/// constructor was keeping quiet.
///
/// Usage is checked across the project under analysis only, which is the whole
/// story for an app. A package published to pub.dev has users the analyzer
/// cannot see, who may extend or instantiate any class of its public API, so
/// for a package (a pubspec without `publish_to: none`) a class the package
/// exports from a library outside `lib/src/` is left alone.
final class AbstractFinalClasses implements Transformation {
  AbstractFinalClasses({required this.enabled});

  @override
  final bool enabled;
  bool _analyzed = false;

  Set<InterfaceElement>? _usedClasses;

  /// The elements a published package exports to its users, or empty for an
  /// app.
  Set<Element> _publicApi = const {};

  /// Whether the project enables `avoid_classes_with_only_static_members`.
  bool _keepPrivateConstructor = false;

  @override
  String get name => 'abstract-final-classes';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    if (!_analyzed) {
      await _analyzeProject(unit);
    }
    final visitor = _AbstractFinalVisitor(
      unit.content,
      _usedClasses!,
      _publicApi,
      keepPrivateConstructor: _keepPrivateConstructor,
    );
    unit.unit.accept(visitor);
    return visitor.edits;
  }

  Future<void> _analyzeProject(ResolvedUnitResult seedUnit) async {
    _analyzed = true;
    final used = <InterfaceElement>{};

    final session = seedUnit.session;
    final root = session.analysisContext.contextRoot.root.path;
    final published = _isPublished(root);
    final publicLib = p.join(root, 'lib');
    final privateLib = p.join(publicLib, 'src');
    final publicApi = <Element>{};
    final files = session.analysisContext.contextRoot.analyzedFiles().where(
      (f) => f.endsWith('.dart'),
    );

    for (final filePath in files) {
      final SomeResolvedUnitResult result;
      try {
        result = await session.getResolvedUnit(filePath);
        // ignore: avoid_catching_errors, the analyzer's own recursion limit.
      } on StackOverflowError {
        continue;
      }
      if (result is! ResolvedUnitResult) continue;
      final collector = _UsageCollector();
      result.unit.accept(collector);
      used.addAll(collector.usedClasses);
      if (published &&
          p.isWithin(publicLib, filePath) &&
          !p.isWithin(privateLib, filePath)) {
        publicApi.addAll(
          result.libraryElement.exportNamespace.definedNames2.values,
        );
      }
    }

    _usedClasses = used;
    _publicApi = publicApi;
    _keepPrivateConstructor =
        seedUnit.analysisOptions.isLintEnabled(_staticMembersLint) ||
        enabledLintRules(root).contains(_staticMembersLint);
  }

  static const _staticMembersLint = 'avoid_classes_with_only_static_members';

  /// Whether the package at [root] can be published: its pubspec does not say
  /// `publish_to: none`.
  static bool _isPublished(String root) {
    final file = File(p.join(root, 'pubspec.yaml'));
    if (!file.existsSync()) return false;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      return yaml is YamlMap && '${yaml['publish_to']}' != 'none';
    } on YamlException {
      return false;
    }
  }
}

class _AbstractFinalVisitor(
  final String source,
  final Set<InterfaceElement> usedClasses,
  final Set<Element> publicApi, {
  required final bool keepPrivateConstructor,
}) extends RecursiveAstVisitor<void> {
  final edits = <SourceEdit>[];

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _collect(node);
    super.visitClassDeclaration(node);
  }

  void _collect(ClassDeclaration node) {
    if (node.abstractKeyword != null) return;
    if (node.finalKeyword != null) return;
    if (node.sealedKeyword != null) return;
    if (node.baseKeyword != null) return;
    if (node.interfaceKeyword != null) return;
    if (node.mixinKeyword != null) return;

    // A static-only holder stands alone. A class that extends, implements, or
    // mixes in another type takes part in a hierarchy and may be created as
    // that type (test mocks are the common case), so leave it as-is.
    if (node.extendsClause != null) return;
    if (node.implementsClause != null) return;
    if (node.withClause != null) return;

    final element = node.declaredFragment?.element;
    if (element == null) return;
    if (usedClasses.contains(element)) return;
    if (publicApi.contains(element)) return;

    // Use the element model to check that every member is static.
    for (final field in element.fields) {
      if (!field.isStatic) return;
    }
    for (final method in element.methods) {
      if (!method.isStatic) return;
    }
    for (final getter in element.getters) {
      if (!getter.isStatic) return;
    }
    for (final setter in element.setters) {
      if (!setter.isStatic) return;
    }

    // Constructors: at most one private preventing constructor (ignoring the
    // implicit default constructor that the compiler synthesizes when none are
    // declared, since abstract final already prevents instantiation).
    ConstructorElement? privateCtorElem;
    for (final ctor in element.constructors) {
      if (!ctor.isOriginDeclaration) continue;
      if (_isPrivatePreventingCtorElement(ctor)) {
        privateCtorElem = ctor;
      } else {
        return;
      }
    }

    // Locate the private constructor's AST node so we can remove it.
    ConstructorDeclaration? privateCtorAst;
    if (privateCtorElem != null) {
      final finder = _CtorFinder(privateCtorElem);
      node.accept(finder);
      privateCtorAst = finder.found;
      if (privateCtorAst == null) return;
    }

    edits.add(
      .new(
        offset: node.classKeyword.offset,
        length: 0,
        replacement: 'abstract final ',
      ),
    );

    if (privateCtorAst != null && !keepPrivateConstructor) {
      final lineStart = _startOfContainingLine(privateCtorAst.offset);
      final lineEnd = _endOfContainingLine(privateCtorAst.end);
      edits.add(
        .new(offset: lineStart, length: lineEnd - lineStart, replacement: ''),
      );
    }
  }

  int _endOfContainingLine(int end) {
    var pos = end;
    while (pos < source.length && source[pos] != '\n') {
      pos++;
    }
    if (pos < source.length) pos++;
    return pos;
  }

  bool _isPrivatePreventingCtorElement(ConstructorElement ctor) {
    if (ctor.name != '_') return false;
    if (ctor.formalParameters.isNotEmpty) return false;
    if (ctor.isFactory) return false;
    return true;
  }

  int _startOfContainingLine(int offset) {
    var pos = offset - 1;
    while (pos >= 0 && source[pos] != '\n') {
      pos--;
    }
    return pos + 1;
  }
}

class _CtorFinder(final ConstructorElement target)
    extends RecursiveAstVisitor<void> {
  ConstructorDeclaration? found;

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.declaredFragment?.element == target) found = node;
  }
}

class _UsageCollector extends RecursiveAstVisitor<void> {
  final usedClasses = <InterfaceElement>{};

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _addFromNamedType(node.extendsClause?.superclass);
    for (final t in node.implementsClause?.interfaces ?? <NamedType>[]) {
      _addFromNamedType(t);
    }
    for (final t in node.withClause?.mixinTypes ?? <NamedType>[]) {
      _addFromNamedType(t);
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    // `.new(...)` / `.named(...)` construct an instance just like a written
    // `TypeName(...)`; the dot-shorthands pass may have produced them, so a
    // class reached only this way must still count as instantiated.
    final type = node.staticType;
    if (type is InterfaceType) usedClasses.add(type.element);
    super.visitDotShorthandConstructorInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    if (type is InterfaceType) usedClasses.add(type.element);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    for (final t in node.onClause?.superclassConstraints ?? <NamedType>[]) {
      _addFromNamedType(t);
    }
    for (final t in node.implementsClause?.interfaces ?? <NamedType>[]) {
      _addFromNamedType(t);
    }
    super.visitMixinDeclaration(node);
  }

  void _addFromNamedType(NamedType? namedType) {
    final type = namedType?.type;
    if (type is InterfaceType) usedClasses.add(type.element);
  }
}

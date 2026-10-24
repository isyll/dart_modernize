import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../../engine/source_edit.dart';
import '../transformation.dart';

/// Ends a declaration whose body is empty with `;` instead of `{}` (Dart
/// 3.13).
///
///     sealed class AuthState {}                ->  sealed class AuthState;
///     class NetworkException implements Exception {}
///                                              ->  class NetworkException implements Exception;
///     mixin Loggable {}                        ->  mixin Loggable;
///
/// Applies to classes, mixin classes, mixins, extension types, and
/// extensions; this is what the lint `empty_container_bodies` asks for. An
/// enum always has a body, and a mixin application (`class B = A with M;`)
/// never has one. A body with a comment inside, or a comment right before its
/// `{`, is left alone.
final class EmptyBodies implements Transformation {
  const EmptyBodies({required this.enabled});

  @override
  final bool enabled;

  @override
  String get name => 'empty-bodies';

  @override
  Future<List<SourceEdit>> editsFor(ResolvedUnitResult unit) async {
    if (!unit.libraryElement.featureSet.isEnabled(.primary_constructors)) {
      return const [];
    }
    final edits = <SourceEdit>[];
    for (final declaration in unit.unit.declarations) {
      final body = switch (declaration) {
        ClassDeclaration(:final body) => body,
        MixinDeclaration(:final body) => body,
        ExtensionDeclaration(:final body) => body,
        ExtensionTypeDeclaration(:final body) => body,
        _ => null,
      };
      if (body is! BlockClassBody || body.members.isNotEmpty) continue;
      final open = body.leftBracket;
      final close = body.rightBracket;
      if (open.precedingComments != null || close.precedingComments != null) {
        continue;
      }
      final previous = open.previous;
      if (previous == null) continue;
      edits.add(
        .new(
          offset: previous.end,
          length: close.end - previous.end,
          replacement: ';',
        ),
      );
    }
    return edits;
  }
}

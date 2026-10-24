import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

/// Which project files each Dart file reaches through its directives.
///
/// When a change in one file breaks another (a caller of a constructor whose
/// signature moved), the error shows up in a file the tool may not have
/// touched. The graph answers which changed files could explain it: those the
/// broken file depends on. Only project files are tracked; `dart:` and other
/// packages' libraries never change during a run.
final class ImportGraph(final String projectPath, final String? packageName) {
  final _edges = <String, Set<String>>{};
  final _exports = <String, Set<String>>{};

  /// Records the `import`, `export`, `part` and `part of` directives of the
  /// file at [path], whose syntax is [unit].
  void add(String path, CompilationUnit unit) {
    final edges = _edges[path] = <String>{};
    final exports = _exports[path] = <String>{};
    for (final directive in unit.directives) {
      final uris = <String?>[];
      if (directive is NamespaceDirective) {
        uris.add(directive.uri.stringValue);
        for (final configuration in directive.configurations) {
          uris.add(configuration.uri.stringValue);
        }
      } else if (directive is PartDirective) {
        uris.add(directive.uri.stringValue);
      } else if (directive is PartOfDirective) {
        uris.add(directive.uri?.stringValue);
      }
      for (final uri in uris) {
        final target = _resolve(path, uri);
        if (target == null) continue;
        edges.add(target);
        if (directive is ExportDirective) exports.add(target);
      }
    }
  }

  /// The files [path] sees declarations from directly: what it imports, the
  /// parts of its library, and everything those re-export, transitively.
  Set<String> directDependencies(String path) {
    final result = <String>{};
    final queue = [...?_edges[path]];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      if (!result.add(next)) continue;
      queue.addAll(_exports[next] ?? const {});
    }
    return result..remove(path);
  }

  /// Every file [path] depends on, directly or through other files.
  Set<String> allDependencies(String path) {
    final result = <String>{};
    final queue = [...?_edges[path]];
    while (queue.isNotEmpty) {
      final next = queue.removeLast();
      if (result.add(next)) queue.addAll(_edges[next] ?? const {});
    }
    return result..remove(path);
  }

  /// The files among [candidates] most likely to explain a new error in
  /// [path]: the direct dependencies first, then the transitive ones.
  Set<String> suspectsFor(String path, Set<String> candidates) {
    final direct = directDependencies(path).intersection(candidates);
    if (direct.isNotEmpty) return direct;
    return allDependencies(path).intersection(candidates);
  }

  /// The absolute path [uri] names from the file at [from], or null when it is
  /// not a file of this project.
  String? _resolve(String from, String? uri) {
    if (uri == null || uri.isEmpty) return null;
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;
    if (parsed.scheme == 'package') {
      final segments = parsed.pathSegments;
      if (segments.length < 2 || segments.first != packageName) return null;
      return p.normalize(p.joinAll([projectPath, 'lib', ...segments.skip(1)]));
    }
    if (parsed.hasScheme) return null;
    return p.normalize(p.join(p.dirname(from), p.fromUri(parsed)));
  }
}

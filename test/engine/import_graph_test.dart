/// Unit spec for the directive graph that traces a new error in one file back
/// to the changed files it depends on.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:dart_modernize/src/engine/import_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _root = p.join(p.current, 'proj');

String _path(String relative) => p.normalize(p.join(_root, relative));

ImportGraph _graph(Map<String, String> files) {
  final graph = ImportGraph(_root, 'app');
  files.forEach((relative, source) {
    graph.add(_path(relative), parseString(content: source).unit);
  });
  return graph;
}

void main() {
  group('ImportGraph', () {
    final graph = _graph({
      'lib/main.dart': "import 'package:app/api.dart';\nimport 'dart:io';\n",
      'lib/api.dart': "export 'src/model.dart';\nimport 'src/util.dart';\n",
      'lib/src/model.dart': "part 'model.g.dart';\n",
      'lib/src/model.g.dart': "part of 'model.dart';\n",
      'lib/src/util.dart': "import 'package:other/other.dart';\n",
    });

    test('follows re-exports for the files a file sees directly', () {
      expect(graph.directDependencies(_path('lib/main.dart')), {
        _path('lib/api.dart'),
        _path('lib/src/model.dart'),
      });
    });

    test('reaches everything transitively, parts included', () {
      expect(graph.allDependencies(_path('lib/main.dart')), {
        _path('lib/api.dart'),
        _path('lib/src/model.dart'),
        _path('lib/src/model.g.dart'),
        _path('lib/src/util.dart'),
      });
    });

    test('suspects direct dependencies before transitive ones', () {
      final changed = {_path('lib/src/model.dart'), _path('lib/src/util.dart')};
      expect(graph.suspectsFor(_path('lib/main.dart'), changed), {
        _path('lib/src/model.dart'),
      });
      expect(
        graph.suspectsFor(_path('lib/main.dart'), {_path('lib/src/util.dart')}),
        {_path('lib/src/util.dart')},
      );
    });

    test('ignores dart: and other packages', () {
      expect(graph.allDependencies(_path('lib/src/util.dart')), isEmpty);
    });
  });
}

class Glob {
  const Glob(String pattern);
}

final class FileFilter {
  final List<Glob> _excludeGlobs;
  FileFilter({List<String> excludePatterns = const []})
    : _excludeGlobs = [for (final pat in excludePatterns) Glob(pat)];
}

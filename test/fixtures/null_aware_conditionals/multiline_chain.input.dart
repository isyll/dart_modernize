Set<String> stringToSet(String? s) => s == null
    ? {}
    : s
          .split(',')
          .map((e) => e.trim())
          .toSet();

int lengthOf(String? s) => s != null
    ? s // the raw text
          .trim()
          .length
    : 0;

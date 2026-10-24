Set<String> stringToSet(String? s) =>
    s?.split(',').map((e) => e.trim()).toSet() ?? {};

int lengthOf(String? s) =>
    s // the raw text
        ?.trim()
        .length ??
    0;

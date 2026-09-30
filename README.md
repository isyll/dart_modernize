<div align="center">

# ⚡ dart_modernize

Your Dart code, brought up to date. Safely.

[![pub package](https://img.shields.io/pub/v/dart_modernize.svg)](https://pub.dev/packages/dart_modernize)
[![sdk](https://img.shields.io/badge/dart-%3E%3D3.13-0175C2.svg)](https://dart.dev)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![style](https://img.shields.io/badge/style-strict-success.svg)](analysis_options.yaml)

</div>

---

Dart keeps getting nicer to write: dot shorthands, switch expressions, patterns, primary constructors. Your old code doesn't get any of it for free.

`dart_modernize` goes through your project and rewrites it the modern way. It understands your types, so it only changes code when the result does exactly the same thing. If it isn't sure, it leaves the line alone.

```sh
dart pub global activate dart_modernize
dart_modernize --dry-run
```

That shows every change as a diff and writes nothing. Happy with it? Run `dart_modernize` and it applies them.

<br>

## 👀 See it work

Here is a small file, before and after. This is real output from the test suite, not a mock-up.

**Before**

```dart
enum Shape { circle, square, triangle }

String describe(Shape s) {
  String label;
  switch (s) {
    case Shape.circle:
      label = 'round';
      break;
    case Shape.square:
    case Shape.triangle:
      label = 'angular';
      break;
  }
  return label;
}

String greet(String who) {
  final msg = 'Hello, ' + who + '!';
  return msg;
}

List<int> gather(List<int> base, List<int>? extra) {
  final all = [...base, if (extra != null) ...extra];
  return all;
}

Queue<int> seedQueue(int seed) {
  var q = Queue<int>();
  q.add(seed);
  q.add(seed + 1);
  return q;
}

Shape defaultShape() {
  return Shape.circle;
}
```

**After**

```dart
enum Shape { circle, square, triangle }

String describe(Shape s) => switch (s) {
  .circle => 'round',
  .square || .triangle => 'angular',
};

String greet(String who) => 'Hello, $who!';

List<int> gather(List<int> base, List<int>? extra) => [...base, ...?extra];

Queue<int> seedQueue(int seed) => Queue<int>()
  ..add(seed)
  ..add(seed + 1);

Shape defaultShape() => .circle;
```

Same behavior, about half the lines. A few more, from fields, methods and the kind of setup code every Flutter app has:

```dart
// before
Level _level = Level.basic;

void promote() {
  _level = Level.premium;
}

static Account guest() {
  return Account(owner: 'guest');
}

sl
  ..registerSingleton<CrashReporter>(crashReporter ?? CrashReporter())
  ..registerLazySingleton<ThemeCubit>(() => ThemeCubit(config: sl()));
```

```dart
// after
Level _level = .basic;

void promote() => _level = .premium;

static Account guest() => .new(owner: 'guest');

sl
  ..registerSingleton<CrashReporter>(crashReporter ?? .new())
  ..registerLazySingleton<ThemeCubit>(() => .new(config: sl()));
```

<br>

## 🧰 What it can do

22 small passes. Each one does one job, and you can switch any of them on or off. All run by default except two, which are opt-in because their diffs are bigger: **sort-members** and **collection-elements**.

| Pass | In plain words |
|:--|:--|
| `dot-shorthands` | `Color.blue` becomes `.blue`, `Service()` becomes `.new()`, when Dart can already tell the type. |
| `switch-expressions` | A `switch` that just picks a value becomes a switch expression. |
| `expression-bodies` | A function that only returns something gets a `=>`. |
| `string-interpolation` | `'Hi ' + name` becomes `'Hi $name'`. |
| `cascades` | `x.a(); x.b();` becomes `x..a()..b()`. |
| `inline-return` | `final x = f(); return x;` becomes `return f();`. |
| `final-locals` | `var` becomes `final` when the variable never changes. |
| `prefer-inferred-types` | `final String name = 'guest'` becomes `final name = 'guest'`. |
| `null-aware-elements` | `[if (a != null) a]` becomes `[?a]`. |
| `null-aware-spread` | `[if (l != null) ...l]` becomes `[...?l]`. |
| `null-aware-conditionals` | `x == null ? null : x[0]` becomes `x?[0]`. |
| `destructure-for-in` | `entry.key` and `entry.value` in a loop become `:key` and `:value` in the header. |
| `destructure-locals` | Three lines that unpack a value become one. |
| `private-named-parameters` | `Foo({required String name}) : _name = name` becomes `Foo({required this._name})`. |
| `primary-constructors` | A class that only stores its constructor arguments gets a one-line header. |
| `super-parameters` | `: super(key: key)` becomes `super.key`. |
| `abstract-final-classes` | A class of only static members becomes `abstract final class`. |
| `organize-imports` | Sorts, groups and removes unused imports. |
| `sort-constructors-first` | Moves constructors to the top of the class. |
| `fix-all` | Runs the same fixes as `dart fix --apply`. |
| `sort-members` (off) | Puts class members in a standard order. |
| `collection-elements` (off) | `list.add(a); list.add(b);` becomes one list literal. |

Every name above works with `--only` and `--no-<name>`. More on that in Usage below.

<br>

## 🖼️ More before and after

Everything below comes from the test suite. Under each example there is a short note on when the pass leaves your code alone.

### Less typing

**Dot shorthands.** Drop the type name when the context already says it: arguments, returns, assignments, comparisons, list items, and the start of a chain.

```dart
// before
Service create() => Service();
visibility = Visibility.hidden;
if (mode == Mode.fast) tick();
Duration remaining(DateTime expiry) => expiry.difference(DateTime.now().toUtc());
Color first() => Color.values.first;

// after
Service create() => .new();
visibility = .hidden;
if (mode == .fast) tick();
Duration remaining(DateTime expiry) => expiry.difference(.now().toUtc());
Color first() => .values.first;
```

It works inside collections, records, patterns, and factory constructors too:

```dart
// before
final routes = [Route(home), Route(settings)];

final options = [
  (StockReadingType.opening, 'Opening', Icons.sunny),
  (StockReadingType.closing, 'Closing', Icons.night),
];

final label = switch (exception) {
  NetworkException(kind: NetworkFailureKind.timeout) => 'timed out',
  _ => 'unknown',
};

factory AuthTokens.fromJson(Map<String, dynamic> json) {
  return AuthTokens(token: json['token'] as String);
}

// after
final routes = <Route>[.new(home), .new(settings)];

final options = <(StockReadingType, String, IconData)>[
  (.opening, 'Opening', Icons.sunny),
  (.closing, 'Closing', Icons.night),
];

final label = switch (exception) {
  NetworkException(kind: .timeout) => 'timed out',
  _ => 'unknown',
};

factory AuthTokens.fromJson(Map<String, dynamic> json) {
  return .new(token: json['token'] as String);
}
```

> Skipped whenever the type isn't certain: `dynamic`, `Object`, a `var`, or a generic type parameter. If `final Color c = Color.blue` has a type you wrote yourself, it becomes `final Color c = .blue`. If the type was redundant, it is dropped instead (see prefer-inferred-types).

**Switch expressions.** A `switch` that only fills in a value becomes a switch expression. Fall-through cases join with `||`, `default` becomes `_`.

```dart
// before
String token;
switch (charCode) {
  case slash:
  case star:
    token = operatorToken(charCode);
    break;
  case comma:
    token = punctuationToken(charCode);
    break;
  default:
    throw FormatException('Invalid');
}

// after
final token = switch (charCode) {
  slash || star => operatorToken(charCode),
  comma => punctuationToken(charCode),
  _ => throw FormatException('Invalid'),
};
```

> Skipped when a case does more than one thing, assigns to different variables, jumps to a label, or doesn't cover every value.

**Expression bodies and string interpolation.**

```dart
// before
int square(int x) {
  return x * x;
}

String row(String a, String b) => '| ' + a + ' | ' + b + ' |';

// after
int square(int x) => x * x;

String row(String a, String b) => '| $a | $b |';
```

> A body with several statements, or with a comment that would get lost, stays a block. Only real strings are interpolated; `1 + 2` is left alone.

**Cascades.** Stop repeating the variable name.

```dart
// before
final paint = Paint();
paint.color = accent;
paint.strokeWidth = 2.0;
paint.style = PaintingStyle.stroke;

final reporter = Reporter(source);
reporter.error('not found');
reporter.errorHint('check spelling');

// after
final paint = Paint()
  ..color = accent
  ..strokeWidth = 2.0
  ..style = PaintingStyle.stroke;

Reporter(source)
  ..error('not found')
  ..errorHint('check spelling');
```

> Skipped if the variable is reassigned, read in the middle of the run, or passed somewhere.

**Inline return.** Passes chain nicely: cascades, then inline-return, then expression-bodies.

```dart
// before
Connection open(String host, String token) {
  var conn = Connection(host);
  conn.open();
  conn.authenticate(token);
  return conn;
}

// after
Connection open(String host, String token) => Connection(host)
  ..open()
  ..authenticate(token);
```

> Skipped when the variable is used more than once or carries a comment.

### Fewer mistakes

**Final locals.** `var` becomes `final` when nothing ever reassigns it.

```dart
// before
var name = user.displayName;
var multiplier = getMultiplier();

for (var item in items) {
  render(item);
}

// after
final name = user.displayName;
final multiplier = getMultiplier();

for (final item in items) {
  render(item);
}
```

> A variable that is changed anywhere, even inside a closure (`+=`, `++`, `=`), stays `var`. So does a classic `for (var i = 0; i < n; i++)`.

**Prefer inferred types.** If the right-hand side already makes the type obvious, you don't have to repeat it.

```dart
// before
final String name = 'guest';
const int retries = 3;
final List<String> tags = [];
final Logger _log = Logger();

// after
final name = 'guest';
const retries = 3;
final tags = <String>[];
final _log = Logger();
```

> The type is kept when the right-hand side isn't obvious, like `final Foo x = compute()`. This follows the analyzer's own `omit_obvious_*` lints, so `dart fix` won't put the type back.

### Null checks, shorter

```dart
// before
List<int> build(int? a) => [if (a != null) a];
List<int> extend(List<int>? extra) => [0, if (extra != null) ...extra];
int? first(List<int>? xs) => xs == null ? null : xs[0];
String label(Box? box, String fallback) => box != null ? box.name : fallback;

// after
List<int> build(int? a) => [?a];
List<int> extend(List<int>? extra) => [0, ...?extra];
int? first(List<int>? xs) => xs?[0];
String label(Box? box, String fallback) => box?.name ?? fallback;
```

> `?x` reads `x` once, where the old code read it twice. So this only applies to plain locals and parameters, never to a getter or a method call. For the `??` form, the value must be non-nullable, otherwise the two versions would give different answers.

### Unpacking values

**Destructure for-in**

```dart
// before
for (final entry in scores.entries) {
  print('${entry.key} = ${entry.value}');
}

// after
for (final MapEntry(:key, :value) in scores.entries) {
  print('$key = $value');
}
```

**Destructure locals**

```dart
// before
final result = computePair();
final a = result.$1;
final b = result.$2;

final p = getPoint();
final x = p.x;
final y = p.y;

// after
final (a, b) = computePair();

final Point(:x, :y) = getPoint();
```

> Skipped when the variable is used for something else too, or when a comment sits between the lines.

### Tidier classes

**Private named parameters**

```dart
// before
class User {
  final String _name;
  User({required String name}) : _name = name;
}

// after
class User {
  final String _name;
  User({required this._name});
}
```

**Primary constructors** (stable since Dart 3.13)

```dart
// before
class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}

class Origin {
  final int x;
  const Origin(this.x);
}

class Record {
  final String name;
  final bool active = true;

  Record(this.name);
}

// after
class Point(final int x, final int y);

class const Origin(final int x);

class Record(final String name) {
  final bool active = true;
}
```

> Skipped when the class is abstract, is extended in the same file, has a second constructor, has a constructor body or an initializer list, or takes a parameter that isn't a plain `this.x`. Factory and redirecting constructors don't count against it and stay in the body. A field with a doc comment or an annotation keeps its class as it is, because the header has nowhere to put them.

**Super parameters**

```dart
// before
class MyWidget extends Widget {
  const MyWidget({Key? key}) : super(key: key);
}

class Book extends Item {
  const Book(String sku, this.cost) : super(sku);
  final double cost;
}

// after
class MyWidget extends Widget {
  const MyWidget({super.key});
}

class Book extends Item {
  const Book(super.sku, this.cost);
  final double cost;
}
```

> Only when the parameter is handed straight to the parent, unchanged.

**Abstract final classes**

```dart
// before
class AppColors {
  AppColors._();
  static const primary = Color(0xFF0175C2);
  static const secondary = Color(0xFF13B9FD);
}

// after
abstract final class AppColors {
  static const primary = Color(0xFF0175C2);
  static const secondary = Color(0xFF13B9FD);
}
```

> Needs the whole project in view: skipped if the class is created, extended, implemented or mixed in anywhere, or already has a class modifier. The empty private constructor goes away, since `abstract final` already blocks instances.

### Housekeeping

**Organize imports**

```dart
// before
import 'models.dart';
import 'dart:math';
import 'dart:convert'; // unused

// after
import 'dart:math';

import 'models.dart';
```

**Sort constructors first** (keeps `sort_constructors_first` happy)

```dart
// before
class Account {
  final String id;
  Account(this.id);
  void deposit(int n) {}
}

// after
class Account {
  Account(this.id);
  final String id;
  void deposit(int n) {}
}
```

**Fix all.** Runs `dart fix --apply`, so it picks up whatever lints your own project turns on, including the ones new Dart versions add.

```dart
// before
class Dog extends Animal {
  String speak() => 'woof';
}

// after
class Dog extends Animal {
  @override
  String speak() => 'woof';
}
```

> The Dart 3.13 lint `use_primary_constructors` does the same job as the primary-constructors pass. They never clash: the pass runs first, so `dart fix` finds nothing left to do.

### Opt-in passes

**Collection elements** (`--collection-elements`). Turns a build-it-step-by-step list into a single literal.

```dart
// before
final items = <Widget>[];
items.add(header);
if (showBody) items.add(body);
for (final s in sections) items.add(s);

// after
final items = <Widget>[
  header,
  if (showBody) body,
  for (final s in sections) s,
];
```

> It's off by default because it turns several statements into one expression, which is a bigger change than any other pass makes. It only starts from an empty literal, and stops at the first statement that reads the list while it's being built.

**Sort members** (`--sort-members`). Puts fields first, then constructors, getters and setters, then methods, sorted by name.

```dart
// before
class Account {
  void deposit(int n) {}
  Account(this.id);
  final String id;
}

// after
class Account {
  final String id;
  Account(this.id);
  void deposit(int n) {}
}
```

> It never changes what your code does, but it can move hundreds of lines and make `git blame` point at the move. That's why it's opt-in. Run it on its own commit:
>
> ```sh
> dart_modernize --only sort-members,sort-constructors-first
> ```
>
> Fields keep their relative order, so a field that reads another field during initialization still runs after it.

<br>

## 🛡️ Will it break my code?

It's built so it can't, in four ways.

* **It checks types, not text.** Every edit comes from fully resolved types, so a rewrite always points at the same thing as before. If it can't prove that, it does nothing.
* **It keeps your program's behavior.** Expressions run the same number of times as before.
* **It double-checks itself.** After editing, it analyzes the changed files again and puts back any file that gained a new error. So a run never leaves code that doesn't compile. (`--no-verify` turns that off.)
* **It won't mix with your work.** It refuses to run on a Git tree with uncommitted changes, so its edits land in their own diff. (`--allow-dirty` overrides that. It doesn't apply under `--dry-run` or `--check`, or outside a Git repo.)

Also good to know:

* Generated code is skipped (`*.g.dart`, `*.freezed.dart`, localization output, anything marked `DO NOT EDIT`).
* Line endings and UTF-8 BOMs are kept, so you only see the lines that really changed (`--line-endings` overrides).
* Running it twice is safe: the second run changes nothing.

The habit that works best: clean tree, `--dry-run`, read the diff, run it, commit.

<br>

## 🛠️ Usage

```
dart_modernize [options] [path]
```

With no path it works on the current directory. With no options it runs every on-by-default pass.

### Start here

```sh
# See what would change, write nothing
dart_modernize --dry-run

# Apply it
dart_modernize
```

### Pick your passes

```sh
# Only these passes
dart_modernize --only cascades
dart_modernize --only cascades,inline-return

# Everything except these
dart_modernize --no-primary-constructors
dart_modernize --no-primary-constructors --no-organize-imports

# Turn on an opt-in pass
dart_modernize --sort-members
dart_modernize --collection-elements
```

Every pass has one switch: `--no-<name>` turns off a pass that's on by default, `--<name>` turns on one that's off. `--only` picks the starting set and the switches adjust it. The order you type them in doesn't matter: passes always run in the same fixed order (see [`doc/ORDERING.md`](doc/ORDERING.md)). `dart_modernize --help` lists every name.

### Pick your folder

```sh
# One directory instead of the whole project
dart_modernize lib/

# A pass selection and a folder together
dart_modernize --only cascades lib/
```

The positional argument is always a path. So `dart_modernize cascades` modernizes a folder called `cascades/`, while `dart_modernize --only cascades` runs the cascades pass.

### Use it in CI

```sh
# Fail if any file would change, write nothing
dart_modernize --check

# Same, and print the diff
dart_modernize --check --dry-run
```

### All options

| Option | What it does |
|:--|:--|
| `-h, --help` | Show usage and exit. |
| `-v, --version` | Print the version and exit. |
| `-n, --dry-run` | Show the changes as a diff, write nothing. |
| `--check` | Write nothing and exit non-zero if any file would change, like `dart format --set-exit-if-changed`. Prints only a summary on its own; add `--dry-run` for the diff too. |
| `--only <name>` | Run only the named passes. Comma-separate them or repeat the flag. |
| `--no-<name>` | Turn off a pass that's on by default, e.g. `--no-primary-constructors`. |
| `--sort-members` | Turn on sort-members. |
| `--collection-elements` | Turn on collection-elements. |
| `--verbose` | Print per-file progress and the passes that changed nothing. |
| `--[no-]color` | Force color on or off. By default it follows the terminal and respects `NO_COLOR`. |
| `--exclude <glob>` | Skip files matching this glob, relative to the project root. Repeatable. |
| `--[no-]verify` | Re-analyze changed files and revert any that gain an error, then exit non-zero. On by default. |
| `--allow-dirty` | Run even with uncommitted changes in Git. |
| `--line-endings <auto\|lf\|crlf>` | Line endings for rewritten files. `auto` (default) keeps what each file had. |

<br>

## 🗂️ Keep settings in your project

Put your choices in `analysis_options.yaml` so nobody has to retype them:

```yaml
dart_modernize:
  enabled:
    - sort-members        # turn on an opt-in pass
  disabled:
    - organize-imports    # turn off a default pass
  exclude:
    - lib/generated/**    # extra files to skip
```

- **`enabled`** turns passes on (handy for the opt-in ones).
- **`disabled`** turns passes off.
- **`exclude`** adds globs on top of `analyzer: exclude:` and any `--exclude` flags.

Command-line flags win over the file. `--only` replaces the file's selection completely. A pass's own switch beats the file for that pass. Since each pass has a switch in one direction only, use `--only` to run something the file turned off. An unknown name, or one listed under both `enabled` and `disabled`, is an error.

<br>

## 🚫 Skipping files

Some files are never touched, and you can add more.

**Always skipped:**

| What | Why |
|:--|:--|
| `*.g.dart`, `*.freezed.dart`, `*.gen.dart` | Generated code |
| `*.gr.dart`, `*.pb.dart`, `*.pbenum.dart` | Router and protobuf output |
| `build/**` | Build output |
| Files that start with `// GENERATED CODE - DO NOT MODIFY`, `// DO NOT EDIT` or `// AUTO-GENERATED` | Generated code with a plain file name. Only the file's leading comments count. |

**Also skipped, automatically:**

- **Flutter localizations.** If you have an `l10n.yaml`, the `gen-l10n` output it points to (default `lib/l10n/app_localizations.dart`) and every per-language file (`app_localizations_fr.dart`, …) are skipped. Without an `l10n.yaml`, a hand-written `app_localizations.dart` is treated like any other file.
- **Your analyzer excludes.** Anything under `analyzer: exclude:` in `analysis_options.yaml`:

  ```yaml
  analyzer:
    exclude:
      - lib/src/proto/**
      - test/golden/**
  ```

**Extra, just for this tool:**

- **`dart_modernize: exclude:`** in `analysis_options.yaml`, for paths you want this tool to skip but the analyzer to keep seeing.
- **`--exclude`** on the command line, for one-off cases:

  ```sh
  dart_modernize --exclude "lib/legacy/**"
  dart_modernize --exclude "lib/legacy/**" --exclude "test/snapshots/**"
  dart_modernize lib/ --exclude "lib/src/vendor/**"
  ```

<br>

## 🧭 How it works

```
  validate  ──▶  resolve  ──▶  transform  ──▶  finalize
   pubspec       full type      type-safe        fix · organize
   + SDK         resolution     edits, in        sort · format
   check                        ordered passes
```

1. **Validate.** Checks that there's a `pubspec.yaml` with an SDK constraint that requires Dart `3.13.0` or newer.
2. **Resolve.** Loads your project with full type information.
3. **Transform.** Runs the passes in groups, in a fixed order. Each group finishes before the next starts, so a pass can build on what an earlier one wrote. The [ordering notes](doc/ORDERING.md) explain why each pass sits where it does.
4. **Finalize.** Runs `dart fix`, organizes imports, sorts members, moves constructors first, then `dart format`.

<br>

## 📋 Requirements

Dart SDK `3.13.0` or newer.

The floor is 3.13 because that's where primary constructors became stable, and one of the passes writes them. The tool refuses to run on a project whose SDK constraint allows anything older, instead of producing code that can't compile.

Stuck on an older SDK? Pin an older release of `dart_modernize`. It keeps working. New language features arrive with new releases of the tool.

<br>

## 📦 Installation

As a global command:

```sh
dart pub global activate dart_modernize
```

Or as a dev dependency:

```sh
dart pub add --dev dart_modernize
```

<br>

## 🤝 Contributing

Contributions are welcome. Read `CONTRIBUTING.md`, then make sure your change passes `dart format`, `dart analyze` and `dart test` before you open a pull request.

<br>

<div align="center">

Released under the **MIT License**.

<sub>Built on the official Dart analyzer. It knows your types, keeps your behavior, and is safe to run twice.</sub>

</div>

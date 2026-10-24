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

28 small passes. Each one does one job, and you can switch any of them on or off. All run by default except three, which are opt-in: **sort-members** and **collection-elements** because their diffs are bigger, and **unmodifiable-of** because the SDK hasn't deprecated the old form yet.

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
| `primary-constructors` | A class or enum that only stores its constructor arguments gets a one-line header. |
| `constructor-shorthands` | `Point(this.x)` becomes `new(this.x)`, `factory Point.fromJson` becomes `factory fromJson`. |
| `empty-bodies` | `class AuthLoading extends AuthState {}` becomes `class AuthLoading extends AuthState;`. |
| `super-parameters` | `: super(key: key)` becomes `super.key`. |
| `null-aware-calls` | `if (cb != null) cb!(x);` becomes `cb?.call(x);`. |
| `future-pause` | `await Future.delayed(d)` becomes `await Future.pause(d)`. |
| `wildcard-parameters` | `(_, __) => ...` becomes `(_, _) => ...`. |
| `abstract-final-classes` | A class of only static members becomes `abstract final class`. |
| `organize-imports` | Sorts, groups and removes unused imports. |
| `sort-constructors-first` | Moves constructors to the top of the class. |
| `fix-all` | Runs the same fixes as `dart fix --apply`. |
| `sort-members` (off) | Puts class members in a standard order. |
| `collection-elements` (off) | `list.add(a); list.add(b);` becomes one list literal. |
| `unmodifiable-of` (off) | `List.unmodifiable(xs)` becomes `List.unmodifiableOf(xs)`, when the type stays the same. |

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

**Null-aware calls.**

```dart
// before
if (onChanged != null) onChanged!(value);
if (widget.onTap != null) {
  widget.onTap!();
}
if (controller != null) controller.dispose();

// after
onChanged?.call(value);
widget.onTap?.call();
controller?.dispose();
```

> Only an `if` with no `else` around a single call on exactly the checked value. That value has to be stable (a local, a parameter, or a final field), and the arguments may not mention it, since it is no longer promoted inside them.

### Small wins

**Future.pause** (Dart 3.13)

```dart
// before
await Future.delayed(const Duration(milliseconds: 300));
await Future.delayed(Duration.zero);

// after
await Future.pause(const Duration(milliseconds: 300));
await Future.pause();
```

> Only when nobody reads the result and there is no callback.

**Wildcard parameters.** Since Dart 3.7, `_` can repeat, so the `__` and `___` written to get around the old rule aren't needed.

```dart
// before
separatorBuilder: (_, __) => const Divider(),
errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),

// after
separatorBuilder: (_, _) => const Divider(),
errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
```

> Named parameters keep their name, which is part of the function's API, and so does a parameter the body reads.

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

class Config {
  final String host;
  final int port;
  const Config({required this.host, this.port = 8080});
}

class Range {
  final int min;
  final int max;
  Range(this.min, this.max) : assert(min <= max);
}

class Scaled {
  final int _value;
  Scaled(int raw) : _value = raw * 2;
}

class Vec {
  final int x;
  final int y;
  const Vec._(this.x, this.y);
  factory Vec.zero() => const Vec._(0, 0);
}

enum Planet {
  mercury(3.3),
  venus(4.8);

  const Planet(this.mass);
  final double mass;
}

// after
class Point(final int x, final int y);

class const Config({required final String host, final int port = 8080});

class Range(final int min, final int max) {
  this : assert(min <= max);
}

class Scaled(int raw) {
  final int _value = raw * 2;
}

class const Vec._(final int x, final int y) {
  factory Vec.zero() => const Vec._(0, 0);
}

enum Planet(final double mass) {
  mercury(3.3),
  venus(4.8),
}
```

Default values, optional `[...]` parameters and `required` are kept as they were. An `assert` moves to the constructor's own body (`this : ...`), and a field set in the initializer list gets its value where it's declared.

> Skipped when the class is abstract, is extended in the same file, has a second generative constructor, or a constructor body or `super(...)` call. Also skipped when the constructor has a doc comment, an annotation or any comment, or a field it would move has one, because the header has nowhere to put them. Factory and redirecting constructors stay in the body. A Flutter widget that forwards `super.key` is left alone unless you opt in (see the `super-parameters` setting under [Keep settings in your project](#%EF%B8%8F-keep-settings-in-your-project)), because that rewrites nearly every widget. A non-const `@immutable` class that keeps an initialized field in its body is skipped too, to dodge a Dart 3.13 lint bug that would make `dart fix` add an invalid `const`.

**Constructor shorthands** (Dart 3.13). Inside the class, a constructor no longer repeats the class name. Calls don't change.

```dart
// before
class Point {
  const Point(this.x, this.y);
  const Point.origin() : x = 0, y = 0;
  factory Point.fromJson(Map<String, Object?> json) => Point(json['x'] as int, json['y'] as int);
  final int x;
  final int y;
}

enum Level {
  low(1),
  high(2);

  const Level(this.value);
  final int value;
}

// after
class Point {
  const new(this.x, this.y);
  const new origin() : x = 0, y = 0;
  factory fromJson(Map<String, Object?> json) => Point(json['x'] as int, json['y'] as int);
  final int x;
  final int y;
}

enum Level {
  low(1),
  high(2);

  new(this.value);
  final int value;
}
```

> An enum constructor is always constant, so its `const` goes too. A comment between the class name and the parameters keeps the old form.

**Empty bodies** (Dart 3.13). Very common in sealed hierarchies and exceptions.

```dart
// before
sealed class AuthState {}
final class AuthInitial extends AuthState {}
class NetworkException implements Exception {}
mixin Loggable {}

// after
sealed class AuthState;
final class AuthInitial extends AuthState;
class NetworkException implements Exception;
mixin Loggable;
```

> A body with a comment inside stays as it is. Enums always have a body.

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

> Needs the whole project in view: skipped if the class is created, extended, implemented or mixed in anywhere, or already has a class modifier. The empty private constructor goes away, since `abstract final` already blocks instances, unless your project turns on `avoid_classes_with_only_static_members`, which that constructor keeps quiet. In a package you publish (no `publish_to: none`), the classes it exports to its users are left alone: their code could extend or create them, and the tool can't see it.

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

**Sort constructors first** (keeps `sort_constructors_first` happy). A class with a `// ignore: sort_constructors_first` comment keeps the order you chose.

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

**Unmodifiable of** (`--unmodifiable-of`). The SDK is preparing to deprecate `List.unmodifiable` and `Map.unmodifiable`, which take an untyped argument.

```dart
// before
final List<int> ids = List.unmodifiable(<int>[1, 2]);
Map<String, int> freeze(Map<String, int> m) => Map.unmodifiable(m);

// after
final List<int> ids = List.unmodifiableOf(<int>[1, 2]);
Map<String, int> freeze(Map<String, int> m) => Map.unmodifiableOf(m);
```

> Only when the result keeps exactly the same type. `List.unmodifiable([1, 2])` with no context is a `List<dynamic>`, while `List.unmodifiableOf` would make it a `List<int>`, so it stays.

<br>

## 🛡️ Will it break my code?

It's built so it can't, in five ways.

* **It checks types, not text.** Every edit comes from fully resolved types, so a rewrite always points at the same thing as before. If it can't prove that, it does nothing.
* **It keeps your program's behavior.** Expressions run the same number of times as before, and default values, doc comments and annotations are never dropped.
* **It double-checks itself.** After each group of passes it compares the errors of every file in memory, before anything is written, and takes back the change behind any new one, even when the error shows up in another file (a caller of a constructor whose signature moved). Once the files are written, `dart analyze` checks the whole project again and reverts whatever still broke. A run never leaves code that doesn't compile. (`--no-verify` turns both checks off.)
* **It can't leave a half-done job.** Before writing, it saves a copy of every file it may touch in `.dart_tool/dart_modernize/backup`. If anything fails, the files are put back. If the process is killed, `dart_modernize --restore` puts them back.
* **It won't mix with your work.** It refuses to run on a Git tree with uncommitted changes, so its edits land in their own diff. (`--allow-dirty` overrides that. It doesn't apply under `--dry-run` or `--check`, or outside a Git repo.)

When the final check has to revert a file, the run still keeps every other change. It prints the usual summary, then the reverted files with the passes that touched them and the `--no-<name>` switches that would skip those passes, and exits with code 2.

Also good to know:

* Generated code is skipped (`*.g.dart`, `*.freezed.dart`, localization output, anything marked `DO NOT EDIT`).
* A file pinned to an older Dart with `// @dart = 2.x` is left alone, since the new syntax wouldn't compile there.
* Only the files the tool changed are formatted. A project formatted to another width, or not formatted at all, keeps its layout everywhere else (`--no-format` turns formatting off, `--line-length` sets the width).
* Line endings and UTF-8 BOMs are kept, so you only see the lines that really changed (`--line-endings` overrides).
* New warnings and infos are listed at the end, without undoing anything, so you know before CI does if you run `dart analyze --fatal-infos`.
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

`--check` and `--dry-run` take every step a real run takes, in memory: the passes, organize imports, sorting, and `dart format` on a scratch copy. `dart fix` only works on files on disk, so for it they list the files it would change instead of showing a diff (and `--check` counts them).

### Exit codes

| Code | Meaning |
|:--|:--|
| `0` | Done. Everything it changed still compiles. |
| `1` | It stopped on an error, or `--check` found something to change. |
| `2` | It kept its changes but had to revert some files that no longer compiled. They are listed. |
| `64` | Bad command line, or a bad `dart_modernize:` section in `analysis_options.yaml`. |

### Older projects

```sh
# Raise the SDK constraint to ^3.13.0 first, then modernize
dart_modernize --upgrade-sdk
```

The tool needs a project on Dart 3.13 or newer. `--upgrade-sdk` raises the `sdk:` constraint in `pubspec.yaml`, runs `pub get`, and removes the `final` and `var` that Dart 3.13 no longer allows on ordinary parameters (`dart fix --code=extraneous_modifier`), before the passes run.

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
| `--[no-]verify` | Check every stage in memory and the written result with `dart analyze`, undo the changes behind any new error, and exit with code 2 if it had to. On by default. |
| `--allow-dirty` | Run even with uncommitted changes in Git. |
| `--line-endings <auto\|lf\|crlf>` | Line endings for rewritten files. `auto` (default) keeps what each file had. |
| `--[no-]format` | Run `dart format` over the files the tool changed. On by default. |
| `--line-length <columns>` | Page width for `dart format`. By default the `formatter: page_width:` of `analysis_options.yaml`, else 80. |
| `--upgrade-sdk` | Raise the SDK constraint to `^3.13.0` first (see Older projects). |
| `--restore` | Put back the files saved by a run that was killed before it finished. |
| `--unmodifiable-of` | Turn on unmodifiable-of. |

<br>

## 🗂️ Keep settings in your project

Put your choices in `analysis_options.yaml` so nobody has to retype them:

```yaml
dart_modernize:
  enabled:
    - sort-members        # turn on an opt-in pass
  disabled:
    - organize-imports    # turn off a default pass
    - format              # leave formatting alone
  exclude:
    - lib/generated/**    # extra files to skip
  line_length: 120        # page width for dart format
  options:
    dot-shorthands:
      constructors: false # keep InputDecoration(...), still shorten .center
    primary-constructors:
      super-parameters: true # also promote widgets that forward super.key
  lint_fixes:
    - unnecessary_underscores # apply this lint's dart fix even if not enabled
```

- **`enabled`** turns passes on (handy for the opt-in ones).
- **`disabled`** turns passes off. `format` turns off the final `dart format`.
- **`exclude`** adds globs on top of `analyzer: exclude:` and any `--exclude` flags.
- **`line_length`** sets the page width for `dart format`, like `--line-length`.
- **`options`** tunes a pass without turning it off. `dot-shorthands` takes `constructors` (default `true`): with `false`, `Foo(...)` is never written `.new(...)`, while enum values and static members still get shortened. `primary-constructors` takes `super-parameters` (default `false`): with `true`, a class whose constructor forwards `super.` parameters is promoted too, which covers nearly every Flutter widget.
- **`lint_fixes`** lists lints whose `dart fix` corrections the tool applies during fix-all, whether or not your `analysis_options.yaml` enables them. Your options file is put back afterwards.

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
3. **Transform.** Runs the passes in groups, in a fixed order. Each group finishes before the next starts, so a pass can build on what an earlier one wrote, and is checked for new errors before the next one starts. The [ordering notes](doc/ORDERING.md) explain why each pass sits where it does.
4. **Finalize.** Runs `dart fix`, organizes imports, sorts members, moves constructors first, then `dart format` over the files it changed.
5. **Verify.** Runs `dart analyze` over the whole project and reverts the changes behind any new error.

`--verbose` prints how long each group took.

<br>

## 📋 Requirements

Dart SDK `3.13.0` or newer.

The floor is 3.13 because that's where primary constructors became stable, and one of the passes writes them. The tool refuses to run on a project whose SDK constraint allows anything older, instead of producing code that can't compile.

Stuck on an older SDK constraint? `--upgrade-sdk` raises it for you. Or pin an older release of `dart_modernize`; it keeps working. New language features arrive with new releases of the tool.

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

Or as a standalone executable: every [GitHub release](https://github.com/isyll/dart_modernize/releases) has one for Linux, macOS and Windows. It still needs a Dart SDK on the machine (it finds it through `DART_SDK`, `FLUTTER_ROOT`, or the `dart` on your `PATH`). Compiled ahead of time, it skips the warm-up of `dart pub global activate`, so it is the fastest way to run the tool, and the most robust on very large projects: under `dart pub global activate`, a deeply nested generated expression (an `operator ==` chaining hundreds of `&&`) can overflow the analyzer's stack. The tool skips such a file and says so, but the executable doesn't need to.

On a large project, run one instance at a time: several runs side by side, next to a Flutter build, can exhaust memory.

<br>

## 🤝 Contributing

Contributions are welcome. Read `CONTRIBUTING.md`, then make sure your change passes `dart format`, `dart analyze` and `dart test` before you open a pull request.

<br>

<div align="center">

Released under the **MIT License**.

<sub>Built on the official Dart analyzer. It knows your types, keeps your behavior, and is safe to run twice.</sub>

</div>

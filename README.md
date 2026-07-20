<div align="center">

# ⚡ dart_modernize

A type-aware codemod that rewrites Dart and Flutter projects to use modern syntax wherever it is safe.

[![pub package](https://img.shields.io/pub/v/dart_modernize.svg)](https://pub.dev/packages/dart_modernize)
[![sdk](https://img.shields.io/badge/dart-%3E%3D3.12-0175C2.svg)](https://dart.dev)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![style](https://img.shields.io/badge/style-strict-success.svg)](analysis_options.yaml)

</div>

---

```sh
dart_modernize
```

It resolves the project with full type information and applies each rewrite only where it provably keeps the same behavior, leaving the code shorter and more idiomatic.

<br>

## 🔍 Before and after

<table>
<tr>
<th align="left">Before</th>
<th align="left">After</th>
</tr>
<tr>
<td>

```dart
final Color c = Color.blue;

Button(
  style: ButtonStyle.flat,
  onTap: Handler.empty(),
);

class Point {
  Point(int x, int y)
      : _x = x,
        _y = y;
  final int _x;
  final int _y;
}
```

</td>
<td>

```dart
final c = Color.blue;

Button(
  style: .flat,
  onTap: .empty(),
);

class Point(int _x, int _y);
```

</td>
</tr>
<tr>
<td>

```dart
const Set<Permission> allowed = {
  Permission.camera,
  Permission.microphone,
  Permission.storage,
};
```

</td>
<td>

```dart
const allowed = <Permission>{
  .camera,
  .microphone,
  .storage,
};
```

</td>
</tr>
<tr>
<td>

```dart
String label;
switch (status) {
  case Status.active:
    label = 'on';
    break;
  default:
    label = 'off';
}
```

</td>
<td>

```dart
final label = switch (status) {
  .active => 'on',
  _ => 'off',
};
```

</td>
</tr>
<tr>
<td>

```dart
final p = Paint();
p.color = accent;
p.strokeWidth = 2.0;

final tags = [
  'base',
  if (extra != null) extra,
];
```

</td>
<td>

```dart
final p = Paint()
  ..color = accent
  ..strokeWidth = 2.0;

final tags = ['base', ?extra];
```

</td>
</tr>
</table>

<br>

## ⚙️ What it does

Eighteen passes, grouped into five families. Each is independently toggleable, and each is skipped on any code where the rewrite cannot be proven safe. All run by default except **sort members**, which is opt-in: it only reorders code and can produce a large diff, so switch it on with `--sort-members` when you want it.

| Feature | Description |
|:--|:--|
| **Dot shorthands** | Collapses `ClassName.member` and `ClassName(...)` to `.member` and `.new(...)` wherever the context type makes the target unambiguous: arguments, return positions, assignments, equality checks, and collection literals, including the head of a selector chain (`DateTime.now().toUtc()` becomes `.now().toUtc()`). |
| **Switch expressions** | Rewrites eligible statement switches as switch expressions with modern pattern syntax: fall-through cases become `\|\|` patterns and `default` becomes `_`. |
| **Expression bodies** | Turns single-`return` block bodies into concise `=>` bodies for functions, methods, getters, and closures. |
| **String interpolation** | Rewrites `'a ' + b + ' c'` concatenation chains into `'a $b c'` interpolation. |
| **Cascades** | Collapses sequential member writes on a fresh local into a `..` cascade; drops the local when unused after the run. |
| **Inline return** | Inlines a local that is immediately returned and used nowhere else: `final x = expr; return x;` becomes `return expr;`. |
| **Final locals** | Replaces `var` with `final` on local variables that are never reassigned, incremented, or compound-assigned. |
| **Prefer inferred types** | Drops a redundant type annotation when the initializer already has exactly that type and that type is obvious from the initializer (locals, top-level consts, and `final`/`const` fields), and moves the type arguments onto a bare collection literal (`List<int> x = []` becomes `var x = <int>[]`). |
| **Null-aware elements** | Folds `if (x != null) x` inside a collection into the null-aware element `?x`. |
| **Null-aware spread** | Folds `if (l != null) ...l` into the null-aware spread `...?l`. |
| **Private named parameters** | Folds constructor boilerplate into the private named parameter form (`this._field`). |
| **Primary constructors** | Promotes eligible classes to the primary constructor form, only when it is provably safe. |
| **Super parameters** | Forwards constructor parameters straight to the superclass with `super.x`. |
| **Organize imports** | Sorts, groups, and prunes unused directives. |
| **Sort members** | Reorders members into the canonical order. **Off by default** (opt in with `--sort-members`); it only moves code but can produce a large diff. |
| **Sort constructors first** | Lifts every constructor ahead of the other members in each class, enum, mixin, and extension type. |
| **Fix all** | Applies the same bulk fixes as `dart fix`, in the same pass. |
| **Abstract final classes** | Adds `abstract final` to classes that expose only static members and are never instantiated, extended, implemented, or mixed in anywhere in the project. |

> Every edit is type checked before it lands. The tool does not change the resolved type, the targeted element, the evaluation count, or the runtime behavior of an expression. If it cannot prove a change is safe, it leaves the code as is.

<br>

## 🧩 Transformations

Each pass below has a minimal before/after and the rule that decides when it is skipped.

### Type-aware syntax

Passes that rely on full type resolution to guarantee the rewrite resolves to the exact same element.

**Dot shorthands**: collapses redundant type names (enum values, static members, named constructors, and unnamed constructors (`.new`)) wherever the context type is unambiguous: arguments, return positions (including a factory constructor's), assignments, equality checks, collection elements, the head of a selector chain, explicitly-typed generic arguments, factory closures, and object/record pattern fields.

```dart
// before
Service create() => Service();
Widget child(Event e) => dispatch(Event());
visibility = Visibility.hidden;
if (mode == Mode.fast) tick();

// after
Service create() => .new();
Widget child(Event e) => dispatch(.new());
visibility = .hidden;
if (mode == .fast) tick();
```

> In a typed declaration whose type the initializer makes obvious, the type is dropped instead (see prefer inferred types); otherwise the annotation stays and supplies the context, so `final Color c = Color.blue` becomes `final Color c = .blue`.

The head of a selector chain collapses too. The context type of the whole chain flows to the leading type name, so a named constructor, static method, or static getter that begins a `.method(...)`, `.getter`, `[index]`, or `!` chain loses its type name while the rest of the chain stays:

```dart
// before
Duration remaining(DateTime expiry) => expiry.difference(DateTime.now().toUtc());
DateTime? parse(String s) => DateTime.tryParse(s)?.toUtc();
Color first() => Color.values.first;

// after
Duration remaining(DateTime expiry) => expiry.difference(.now().toUtc());
DateTime? parse(String s) => .tryParse(s)?.toUtc();
Color first() => .values.first;
```

A generic call pins its type from an explicit `<...>` rather than its arguments, so the argument then has a context, and a factory closure takes its context from the function type it is written against. Together these collapse the common service-locator / dependency-injection pattern:

```dart
// before
sl
  ..registerSingleton<CrashReporter>(crashReporter ?? CrashReporter())
  ..registerLazySingleton<ThemeCubit>(() => ThemeCubit(storage: sl()));

// after
sl
  ..registerSingleton<CrashReporter>(crashReporter ?? .new())
  ..registerLazySingleton<ThemeCubit>(() => .new(storage: sl()));
```

Both are skipped when the type is still inferred from that very argument or closure (no explicit `<...>`), since collapsing would leave nothing to infer it from.

A factory constructor's body returns the class's own type, so a `return` (or `=>`) that builds it collapses too:

```dart
// before
factory AuthTokens.fromJson(Map<String, dynamic> json) {
  return AuthTokens(token: json['token'] as String);
}

// after
factory AuthTokens.fromJson(Map<String, dynamic> json) {
  return .new(token: json['token'] as String);
}
```

A constant inside an object or record pattern field matches that field, so it collapses against the field's type:

```dart
// before
final label = switch (exception) {
  NetworkException(kind: NetworkFailureKind.timeout) => 'timed out',
  _ => 'unknown',
};

// after
final label = switch (exception) {
  NetworkException(kind: .timeout) => 'timed out',
  _ => 'unknown',
};
```

In collection literals the element type flows down to each element, and an untyped literal is given an explicit type so the shorthand is well defined:

```dart
// before
final routes = [Route(home), Route(settings)];
List<Widget> build() => [Widget(a: a, b: b), Widget(a: 'genial')];

// after
final routes = <Route>[.new(home), .new(settings)];
List<Widget> build() => [.new(a: a, b: b), .new(a: 'genial')];
```

> Refuses to apply when the context type is `dynamic`, `Object`, an inferred `var`, or a type variable, anywhere the shortened form would not resolve to the exact same element.

Record fields collapse too. Each field takes its context from the matching field of the record's type (positional by index, named by name), and an untyped list of records has its inferred element type hoisted so the field shorthands resolve:

```dart
// before
final options = [
  (StockReadingType.opening, 'Opening', Icons.sunny),
  (StockReadingType.closing, 'Closing', Icons.night),
];

// after
final options = <(StockReadingType, String, IconData)>[
  (.opening, 'Opening', Icons.sunny),
  (.closing, 'Closing', Icons.night),
];
```

> The record element type is hoisted only when every field is precise; a field typed `dynamic`, `Object`, `Null`, or an unresolved type variable leaves the record untouched.

**Switch expressions**: rewrites an eligible statement `switch` as a switch expression with modern pattern syntax: fall-through cases collapse to `||` patterns, `default` becomes `_`, and a `throw` stays inline.

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

> Also handles the `return`-per-case form, producing `return switch (…) { … };`. Left untouched when an arm runs more than one statement, branches assign different targets, breaks or continues to a label, has side effects, or is not exhaustive: anything where the expression form would change behavior.

### Concise expressions

Shorter bodies, strings, builder sequences, and type annotations, without changing any value.

**Expression bodies**: turns a single-`return` block body into a `=>` body for functions, methods, getters, and closures.

```dart
// before
int square(int x) {
  return x * x;
}

// after
int square(int x) => x * x;
```

> Kept as a block when it holds more than one statement, or a comment the arrow form would silently drop.

**String interpolation**: rewrites `+` concatenation chains into interpolation.

```dart
// before
String greet(String name) => 'Hello, ' + name + '!';
String row(String a, String b) => '| ' + a + ' | ' + b + ' |';

// after
String greet(String name) => 'Hello, $name!';
String row(String a, String b) => '| $a | $b |';
```

> Only when every piece is a side-effect-free `String`. Arithmetic `+` and method-call operands are left exactly as written.

**Cascades**: collapses sequential member writes and calls on a freshly declared local into a single cascade. When the local is unused after the run it is dropped entirely.

```dart
// before: local kept
final paint = Paint();
paint.color = accent;
paint.strokeWidth = 2.0;
paint.style = PaintingStyle.stroke;

// after: local kept
final paint = Paint()
  ..color = accent
  ..strokeWidth = 2.0
  ..style = PaintingStyle.stroke;

// before: local unused after run
final reporter = Reporter(source);
reporter.error('not found');
reporter.errorHint('check spelling');

// after: dropped to a bare statement cascade
Reporter(source)
  ..error('not found')
  ..errorHint('check spelling');
```

> Applies only when the target is not reassigned, read between writes, or passed as an argument within the run, and no right-hand side reads the target.

**Inline return**: inlines a local whose only remaining use is an immediate bare `return`.

```dart
// before
final value = compute();
return value;

// after
return compute();
```

This also handles the intermediate form produced by the **cascades** pass in a subsequent run:

```dart
// before (after cascades)
var conn = Connection(host)
  ..open()
  ..authenticate(token);
return conn;

// after
return Connection(host)
  ..open()
  ..authenticate(token);
```

> Skipped when the local has more than one use, carries a comment, is declared alongside other variables in one statement, or the return is not an immediate bare reference to the local.

**Final locals**: replaces `var` with `final` on local variables that are never reassigned anywhere in the enclosing function body.

```dart
// before
var name = user.displayName;
var multiplier = getMultiplier();
print(name);
return multiplier * rate;

// after
final name = user.displayName;
final multiplier = getMultiplier();
print(name);
return multiplier * rate;
```

> Skipped when the variable is reassigned, compound-assigned (`+=`, etc.), or incremented/decremented (`++`/`--`) anywhere in the enclosing body, including inside closures.

**Prefer inferred types**: drops a type annotation the initializer already implies, and moves the type arguments onto a bare collection literal.

```dart
// before
final String name = 'guest';
const int retries = 3;
final List<String> tags = [];
final Logger _log = Logger();
final Client _client = .new();

// after
final name = 'guest';
const retries = 3;
final tags = <String>[];
final _log = Logger();
final _client = Client();
```

> Applies only when the initializer's inferred type is exactly the declared type **and** that type is obvious from the initializer, matching the analyzer's `omit_obvious_*` / `specify_nonobvious_*` rules. A literal, an explicitly-typed collection literal, a spelled-out constructor call, a cast, or a cascade/prefix over one of these is obvious; a method call, property access, bare identifier, or generic constructor with inferred type arguments is not, and keeps its annotation (dropping it would trip `specify_nonobvious_*`, which `dart fix` then reverts). Covers local finals/consts/bare-typed locals, top-level consts, and `final`/`const` fields with an initializer. Dropping the type is preferred over the `.new()` shorthand, so a `final Foo _x = Foo()` field becomes `final _x = Foo()`; a declaration already written with a dot-shorthand constructor (`final Foo _x = .new()`) is expanded to `final _x = Foo()` for the same reason (a static-member shorthand such as `.zero` keeps its annotation, since expanding it would leave a non-obvious property access). Mutable fields and non-const top-level variables are left alone.

### Null-aware collections

The Dart 3.8 null-aware collection syntax, applied only when the rewrite preserves single evaluation.

**Null-aware elements**: folds a null guard inside a collection into `?x`.

```dart
// before
List<int> build(int? a) => [if (a != null) a];

// after
List<int> build(int? a) => [?a];
```

**Null-aware spread**: folds a guarded spread into `...?l`.

```dart
// before
List<int> build(List<int>? extra) => [0, if (extra != null) ...extra];

// after
List<int> build(List<int>? extra) => [0, ...?extra];
```

> `?expr` evaluates the operand **once**, where the old `if`/value form evaluated it twice. So these apply only to a stable, side-effect-free reference (a local or const). Getters, method calls, and index lookups are left alone.

### Constructor shorthands

Folds constructor boilerplate into the shorthands the language now provides.

**Private named parameters**: folds the "public param, private field" boilerplate into a private named parameter.

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

> Left alone when the parameter is transformed, renamed, or reused elsewhere in the initializer list.

**Primary constructors**: promotes a class whose only job is to bind constructor parameters to fields.

```dart
// before
class Point {
  final int x;
  final int y;
  Point(this.x, this.y);
}

// after
class Point(final int x, final int y);
```

> Skipped when the class has another constructor, a constructor body, an initializer list, or a non-`this.` parameter.

**Super parameters**: forwards a constructor parameter straight to the superclass.

```dart
// before
class MyWidget extends Widget {
  const MyWidget({Key? key}) : super(key: key);
}

// after
class MyWidget extends Widget {
  const MyWidget({super.key});
}
```

> Only when the parameter is passed through unchanged and not otherwise read, renamed, or given a different default.

### Project hygiene

Whole-file cleanup that runs after the structural passes settle.

**Organize imports**: sorts directives into `dart:`, `package:`, then relative groups, separates them with a blank line, and prunes the unused.

```dart
// before
import 'models.dart';
import 'dart:math';
import 'dart:convert'; // unused

// after
import 'dart:math';

import 'models.dart';
```

**Sort members** (off by default; switch it on with `--sort-members`, or run it alone with `--only sort-members`): reorders class members into canonical order (fields, constructors, getters/setters, then methods), sorting by name within each group. Fields keep their declared order, so field initialization order never changes. It is opt-in because it only reorders code (never changing behavior) yet is the biggest single source of diff noise, which buries the real modernizations under moved lines.

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

**Sort constructors first**: lifts every constructor ahead of the other members of a class, enum, mixin, or extension type, satisfying the `sort_constructors_first` lint. It runs after sort members, so the two compose: sort members settles the canonical order, then this pass moves the constructors to the front. Attached doc comments and annotations travel with their constructor.

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

**Fix all**: applies the same bulk fixes as `dart fix` in the same pass: adding `@override`, dropping `new`, and more.

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

**Abstract final classes**: adds `abstract final` to classes that expose only static members and are never instantiated, extended, implemented, or mixed in anywhere in the analyzed project. A lone private preventing constructor is removed because `abstract final` already prevents external instantiation.

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

> Skipped when the class is extended, implemented, or instantiated anywhere in the analyzed project, or already carries any class modifier. Requires full project analysis, so it runs as the final pass after all structural rewrites have settled.

<br>

## 📋 Requirements

Dart SDK `3.12.0` or newer.

The minimum SDK is fixed per release. When a future Dart version ships new syntax, a new major version of `dart_modernize` adds support for it. Staying on an older SDK? Pin the matching release and it keeps working.

<br>

## 📦 Installation

Globally, as a CLI:

```sh
dart pub global activate dart_modernize
```

Or per project, as a dev dependency:

```sh
dart pub add --dev dart_modernize
```

<br>

## 🛠️ Usage

```
dart_modernize [options] [path]
```

`dart_modernize` takes an optional path and a handful of flags. With no path it runs in the current directory; with no flags it runs every pass. Nothing is written until you drop `--dry-run`, so start there and review the diff.

### Start here

```sh
# Preview every change as a unified diff, writing nothing
dart_modernize --dry-run

# Apply the changes once the diff looks right
dart_modernize
```

### Choose which passes run

Every pass runs by default except **sort-members**, which is opt-in. Adjust the set three ways, which compose:

```sh
# Allow-list: run ONLY the passes you name (comma-separate or repeat --only)
dart_modernize --only cascades
dart_modernize --only cascades,inline-return

# Deny-list: run everything EXCEPT the passes you switch off
dart_modernize --no-primary-constructors
dart_modernize --no-primary-constructors --no-organize-imports

# Switch on an off-by-default pass (currently just sort-members)
dart_modernize --sort-members
```

Each pass has exactly one switch: an on-by-default pass takes `--no-<name>` (turn it off), an off-by-default pass takes `--<name>` (turn it on). `--only` sets the starting set (the defaults when omitted); `--no-<name>` removes from it and `--<name>` adds to it, so the switches compose with `--only`. Command-line order never matters: passes always run in their fixed pipeline order (see [`doc/ORDERING.md`](doc/ORDERING.md)). The pass names are those listed under **What it does** above and printed by `dart_modernize --help`.

### Choose where it runs

```sh
# Modernize one directory instead of the whole project
dart_modernize lib/

# A selection and a path together: run only cascades, over lib/
dart_modernize --only cascades lib/
```

The positional argument is **always a path**, so a directory named after a pass is never mistaken for a selection: `dart_modernize cascades` modernizes the `cascades/` folder, whereas `dart_modernize --only cascades` runs the cascades pass.

### Gate CI

```sh
# Exit non-zero if any file would change, and write nothing
dart_modernize --check

# Same gate, but also print the diff of what would change
dart_modernize --check --dry-run
```

### Options

| Option | Description |
|:--|:--|
| `-h, --help` | Show usage and exit. |
| `-v, --version` | Print the version and exit. |
| `-n, --dry-run` | Preview changes as a unified diff; write nothing. |
| `--check` | Write nothing and exit non-zero if any file would change, for gating CI (like `dart format --set-exit-if-changed`). Prints only a summary on its own; combine with `--dry-run` to also print the diff. |
| `--only <name>` | Run **only** the named passes and skip the rest. Comma-separate or repeat the flag to name several (`--only cascades,inline-return`). Names are the passes listed above; without `--only`, every pass runs. |
| `--no-<name>` | Turn an on-by-default pass off, e.g. `--no-primary-constructors`. Composes with `--only` (removes the pass from the selected set). |
| `--sort-members` | Switch on sort-members, the one opt-in pass (off by default because it only reorders members but can produce a large diff). Composes with `--only` (adds it to the selected set). |
| `--verbose` | Print per-file progress and passes that made no change. |
| `--[no-]color` | Force ANSI color on or off. Default: auto-detect, so color is on when writing to a terminal and off when piped or when `NO_COLOR` is set. `--color` forces it on (handy when piping to a pager); `--no-color` forces it off. |
| `--exclude <glob>` | Extra glob pattern to skip, relative to the project root. Repeatable. |
| `--[no-]verify` | Re-analyze changed files after editing and revert any that gain a new error, then exit non-zero. On by default; `--no-verify` skips the extra analysis. |
| `--allow-dirty` | Run even when the Git working tree has uncommitted changes. By default the tool refuses on a dirty tree, so its edits land in their own reviewable diff. Skipped when the target is not in a Git repository or under `--dry-run`/`--check`. |
| `--line-endings <auto\|lf\|crlf>` | Line endings for files the tool rewrites. `auto` (default) keeps each file's existing endings; `lf` or `crlf` forces one. A UTF-8 BOM is always preserved. |

Run `dart_modernize --help` for the same reference, always current.

<br>

## 🚫 Excluding files

The tool skips files in four ways, checked in order.

**Built-in**: always excluded, no configuration required.

| Pattern | Reason |
|:--|:--|
| `*.g.dart`, `*.freezed.dart`, `*.gen.dart` | Code-generation outputs |
| `*.gr.dart`, `*.pb.dart`, `*.pbenum.dart` | Router and protobuf outputs |
| `build/**` | Build directory |
| leading `// GENERATED CODE - DO NOT MODIFY`, `// DO NOT EDIT`, `// AUTO-GENERATED` | Generated code that uses a plain file name (e.g. some `build_runner` outputs). The marker is only honored in the file's leading comment block. |

**`l10n.yaml`**: honored automatically. When a project declares one, the `flutter gen-l10n` output it points at (`output-dir` and `output-localization-file`, defaulting to `lib/l10n/app_localizations.dart`) and every per-locale sibling (`app_localizations_fr.dart`, …) are skipped, since they are regenerated on the next build. Without an `l10n.yaml`, a hand-written `app_localizations.dart` is treated like any other source.

**`analysis_options.yaml`**: honored automatically. Any pattern listed under `analyzer: exclude:` is picked up without any extra flags:

```yaml
analyzer:
  exclude:
    - lib/src/proto/**
    - test/golden/**
```

**`--exclude` flag**: for ad-hoc patterns not already in `analysis_options.yaml`. The pattern is matched against the path relative to the project root and the flag can be repeated:

```sh
# Exclude a single directory
dart_modernize --exclude "lib/legacy/**"

# Exclude multiple paths
dart_modernize --exclude "lib/legacy/**" --exclude "test/snapshots/**"

# Combine with a target path
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

1. **Validate.** Checks that a `pubspec.yaml` exists and declares an SDK constraint, so the project can be resolved.
2. **Resolve.** Loads the project with full type resolution, library by library.
3. **Transform.** Runs a fixed sequence of pass groups. Each group is resolved once and applied before the next runs, so a pass that builds on an earlier one (a shorthand over a switch expression another pass produced, say) reads the finished result. See [`doc/ORDERING.md`](doc/ORDERING.md).
4. **Finalize.** Applies `dart fix`, organizes imports, sorts members, and runs `dart format`.

Re-running is safe: the first run does all the work and later runs change nothing. The tool is idempotent by design.

<br>

## 🛡️ Safety

* **Dry run first.** Produces a full diff before touching any file.
* **Skips generated code.** Ignores `*.g.dart`, `*.freezed.dart`, and other build outputs, `flutter gen-l10n` localization files, and any file carrying a `DO NOT EDIT` header.
* **Refuses ambiguity.** Will not apply a shorthand when the context type is too imprecise to guarantee an identical result.
* **Preserves evaluation.** Keeps the number of times an expression runs identical, so it skips sugar like `?expr` unless the operand is provably stable and side-effect free.
* **Type-checked edits.** Every rewrite is computed from fully resolved types, so the targeted element and the static type stay identical.
* **Verifies and rolls back.** After editing, re-analyzes the changed files and restores any that gained a new error, so a run never leaves a file that no longer compiles (`--no-verify` opts out).
* **Refuses a dirty tree.** Stops before writing if the Git working tree has uncommitted changes, so the modernization stays in its own reviewable diff (`--allow-dirty` opts out; skipped outside a repo and under `--dry-run`/`--check`).
* **Preserves line endings and BOM.** Each file's original CRLF/LF endings and any UTF-8 BOM are restored after formatting, so an edit shows only the lines that changed instead of a whole-file whitespace diff (`--line-endings` overrides).

Run on a clean working tree, review the diff, then commit.

<br>

## 🤝 Contributing

Contributions are welcome. Read `CONTRIBUTING.md`, then make sure your change passes `dart format`, `dart analyze`, and `dart test` before opening a pull request.

<br>

<div align="center">

Released under the **MIT License**.

<sub>Built with the official Dart analyzer. Type aware, behavior preserving, idempotent.</sub>

</div>

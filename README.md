<div align="center">

# ⚡ dart_modernize

### Drag your codebase into the future, one command at a time.

A type aware codemod that rewrites Dart and Flutter projects to use modern syntax everywhere it is safe.

[![pub package](https://img.shields.io/pub/v/dart_modernize.svg)](https://pub.dev/packages/dart_modernize)
[![sdk](https://img.shields.io/badge/dart-%3E%3D3.12-0175C2.svg)](https://dart.dev)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![style](https://img.shields.io/badge/style-strict-success.svg)](analysis_options.yaml)

</div>

---

```sh
dart_modernize
```

One command. Full type resolution. Zero behavior changes. Your code comes out cleaner, shorter, and unmistakably modern.

<br>

## ✨ See it in action

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
const allowed = <Permission>{
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

<div align="center"><sub>Same types. Same elements. Same behavior. Just modern.</sub></div>

<br>

## 🚀 What it does

Eighteen focused passes, grouped into five families. Each one is independently toggleable, and each leaves your code alone the moment a rewrite cannot be proven safe.

| | Feature | Description |
|:--:|:--|:--|
| 🎯 | **Dot shorthands** | Collapses `ClassName.member` and `ClassName(...)` to `.member` and `.new(...)` wherever the context type makes the target unambiguous: arguments, return positions, assignments, equality checks, and collection literals. |
| 🔀 | **Switch expressions** | Rewrites eligible statement switches as switch expressions with modern pattern syntax: fall-through cases become `\|\|` patterns and `default` becomes `_`. |
| ➡️ | **Expression bodies** | Turns single-`return` block bodies into concise `=>` bodies for functions, methods, getters, and closures. |
| 🧵 | **String interpolation** | Rewrites `'a ' + b + ' c'` concatenation chains into clean `'a $b c'` interpolation. |
| 🌊 | **Cascades** | Collapses sequential member writes on a fresh local into a `..` cascade; drops the local when unused after the run. |
| ↩️ | **Inline return** | Inlines a local that is immediately returned and used nowhere else: `final x = expr; return x;` becomes `return expr;`. |
| 📌 | **Final locals** | Replaces `var` with `final` on local variables that are never reassigned, incremented, or compound-assigned. |
| 🏷️ | **Prefer inferred types** | Drops a redundant type annotation when the initializer already has exactly that type (locals, top-level consts, and `final`/`const` fields), and moves the type arguments onto a bare collection literal (`List<int> x = []` becomes `var x = <int>[]`). |
| ❓ | **Null-aware elements** | Folds `if (x != null) x` inside a collection into the null-aware element `?x`. |
| ❔ | **Null-aware spread** | Folds `if (l != null) ...l` into the null-aware spread `...?l`. |
| 🔒 | **Private named parameters** | Folds verbose constructor boilerplate into the modern private named parameter form (`this._field`). |
| 🏗️ | **Primary constructors** | Promotes eligible classes to the primary constructor form, only when it is provably safe. |
| ⬆️ | **Super parameters** | Forwards constructor parameters straight to the superclass with `super.x`. |
| 📦 | **Organize imports** | Sorts, groups, and prunes unused directives. |
| 🔤 | **Sort members** | Reorders members into the canonical order. |
| 🔝 | **Sort constructors first** | Lifts every constructor ahead of the other members in each class, enum, mixin, and extension type. |
| 🩹 | **Fix all** | Applies the same bulk fixes as `dart fix`, in the same pass. |
| 🏛️ | **Abstract final classes** | Adds `abstract final` to classes that expose only static members and are never instantiated, extended, implemented, or mixed in anywhere in the project. |

> Every edit is type checked before it lands. The tool **never** changes the resolved type, the targeted element, the evaluation count, or the runtime behavior of an expression. If it cannot prove a change is safe, it leaves your code alone.

<br>

## 🔬 Every transformation, before & after

Each pass is shown as a minimal before/after, paired with the safety rule that decides when it stays its hand.

### 🧠 Type-aware syntax

Passes that lean on full type resolution to guarantee the rewrite resolves to the exact same element.

**🎯 Dot shorthands**: collapses redundant type names (enum values, static members, named constructors, and unnamed constructors (`.new`)) wherever the context type is unambiguous: arguments, return positions, assignments, equality checks, and collection elements.

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

> In a typed declaration the type is dropped instead, so `final Color c = Color.blue` becomes `final c = Color.blue` (see prefer inferred types).

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

**🔀 Switch expressions**: rewrites an eligible statement `switch` as a switch expression with modern pattern syntax: fall-through cases collapse to `||` patterns, `default` becomes `_`, and a `throw` stays inline.

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

### ✂️ Concise expressions

Trimming ceremony from bodies, strings, builder sequences, and type annotations without moving a single value.

**➡️ Expression bodies**: turns a single-`return` block body into a `=>` body for functions, methods, getters, and closures.

```dart
// before
int square(int x) {
  return x * x;
}

// after
int square(int x) => x * x;
```

> Kept as a block when it holds more than one statement, or a comment the arrow form would silently drop.

**🧵 String interpolation**: rewrites `+` concatenation chains into interpolation.

```dart
// before
String greet(String name) => 'Hello, ' + name + '!';
String row(String a, String b) => '| ' + a + ' | ' + b + ' |';

// after
String greet(String name) => 'Hello, $name!';
String row(String a, String b) => '| $a | $b |';
```

> Only when every piece is a side-effect-free `String`. Arithmetic `+` and method-call operands are left exactly as written.

**🌊 Cascades**: collapses sequential member writes and calls on a freshly declared local into a single cascade. When the local is unused after the run it is dropped entirely.

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

**↩️ Inline return**: inlines a local whose only remaining use is an immediate bare `return`.

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

**📌 Final locals**: replaces `var` with `final` on local variables that are never reassigned anywhere in the enclosing function body.

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

**🏷️ Prefer inferred types**: drops a type annotation the initializer already implies, and moves the type arguments onto a bare collection literal.

```dart
// before
final String name = user.displayName;
const int retries = 3;
final List<String> tags = [];
final Logger _log = Logger();

// after
final name = user.displayName;
const retries = 3;
final tags = <String>[];
final _log = Logger();
```

> Applies only when the initializer's inferred type is exactly the declared type. Covers local finals/consts/bare-typed locals, top-level consts, and `final`/`const` fields with an initializer. Dropping the type is preferred over the `.new()` shorthand, so a `final Foo _x = Foo()` field becomes `final _x = Foo()`. Mutable fields and non-const top-level variables are left alone.

### ❓ Null-aware collections

The Dart 3.8 null-aware collection syntax, applied only when the rewrite preserves single evaluation.

**❓ Null-aware elements**: folds a null guard inside a collection into `?x`.

```dart
// before
List<int> build(int? a) => [if (a != null) a];

// after
List<int> build(int? a) => [?a];
```

**❔ Null-aware spread**: folds a guarded spread into `...?l`.

```dart
// before
List<int> build(List<int>? extra) => [0, if (extra != null) ...extra];

// after
List<int> build(List<int>? extra) => [0, ...?extra];
```

> `?expr` evaluates the operand **once**, where the old `if`/value form evaluated it twice. So these apply only to a stable, side-effect-free reference (a local or const). Getters, method calls, and index lookups are left alone.

### 🧱 Constructor sugar

Folding constructor boilerplate into the shorthands the language now provides.

**🔒 Private named parameters**: folds the old "public param, private field" boilerplate into a private named parameter.

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

**🏗️ Primary constructors**: promotes a class whose only job is to bind constructor parameters to fields.

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

**⬆️ Super parameters**: forwards a constructor parameter straight to the superclass.

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

### 🧹 Project hygiene

Whole-file cleanup that runs after the structural passes settle.

**📦 Organize imports**: sorts directives into `dart:`, `package:`, then relative groups, separates them with a blank line, and prunes the unused.

```dart
// before
import 'models.dart';
import 'dart:math';
import 'dart:convert'; // unused

// after
import 'dart:math';

import 'models.dart';
```

**🔤 Sort members**: reorders class members into canonical order (fields, constructors, getters/setters, then methods), sorting by name within each group. Fields keep their declared order, so field initialization order never changes.

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

**🔝 Sort constructors first**: lifts every constructor ahead of the other members of a class, enum, mixin, or extension type, satisfying the `sort_constructors_first` lint. It runs after sort members, so the two compose: sort members settles the canonical order, then this pass moves the constructors to the front. Attached doc comments and annotations travel with their constructor.

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

**🩹 Fix all**: applies the same bulk fixes as `dart fix` in the same pass: adding `@override`, dropping `new`, and more.

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

**🏛️ Abstract final classes**: adds `abstract final` to classes that expose only static members and are never instantiated, extended, implemented, or mixed in anywhere in the analyzed project. A lone private preventing constructor is removed because `abstract final` already prevents external instantiation.

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

## 📐 Requirements

<div align="center">

**Dart SDK `3.12.0` or newer**

</div>

The minimum SDK is fixed per release. When a future Dart version ships new syntax, a new major version of `dart_modernize` adds support for it. Staying on an older SDK? Pin the matching release and it keeps working.

<br>

## 📥 Install

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

```sh
# Preview every change without writing a single byte (start here)
dart_modernize --dry-run

# Apply across the whole project
dart_modernize

# Target a path
dart_modernize lib/

# Pick and choose
dart_modernize --no-primary-constructors --dry-run
```

<details>
<summary><b>Full option list</b></summary>

<br>

Run `dart_modernize --help` for the complete, always up to date reference. Every transformation can be toggled independently, paths can be excluded, and formatting is configurable.

</details>

<br>

## 🧠 How it works

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

Re-running is safe: the first run does all the work and later runs change nothing. The tool is **idempotent** by design.

<br>

## 🛡️ Safety

* 🔍 **Dry run first.** Produces a full diff before touching any file.
* 🚫 **Skips generated code.** Ignores `*.g.dart`, `*.freezed.dart`, and other build outputs.
* ⚖️ **Refuses ambiguity.** Will not apply a shorthand when the context type is too imprecise to guarantee an identical result.
* 🔁 **Preserves evaluation.** Keeps the number of times an expression runs identical, so it skips sugar like `?expr` unless the operand is provably stable and side-effect free.
* ✅ **Type-checked edits.** Every rewrite is computed from fully resolved types, so the targeted element and the static type stay identical.

Run on a clean working tree, review the diff, then commit with confidence.

<br>

## 🤝 Contributing

Contributions are welcome. Read `CONTRIBUTING.md`, then make sure your change passes `dart format`, `dart analyze`, and `dart test` before opening a pull request.

<br>

<div align="center">

Released under the **MIT License**.

<sub>Built with the official Dart analyzer. Type aware, behavior preserving, idempotent.</sub>

</div>

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
final Color c = .blue;

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
</table>

<div align="center"><sub>Same types. Same elements. Same behavior. Just modern.</sub></div>

<br>

## 🚀 What it does

| | Feature | Description |
|:--:|:--|:--|
| 🎯 | **Dot shorthands** | Collapses `ClassName.member` and `ClassName(...)` to `.member` and `.new(...)` wherever the context type makes the target unambiguous, including return positions, typed variables, arguments, and collection literals. |
| 🔒 | **Private named parameters** | Folds verbose constructor boilerplate into the modern private named parameter form (`this._field`). |
| 🏗️ | **Primary constructors** | Promotes eligible classes to the primary constructor form, only when it is provably safe. |
| 🔀 | **Switch expressions** | Rewrites eligible statement switches as switch expressions with modern pattern syntax: fall-through cases become `\|\|` patterns and `default` becomes `_`. |
| 📦 | **Organize imports** | Sorts, groups, and prunes unused directives. |
| 🔤 | **Sort members** | Reorders members into the canonical order. |
| 🩹 | **Fix all** | Applies the same bulk fixes as `dart fix`, in the same pass. |

> Every edit is type checked before it lands. The tool **never** changes the resolved type, the targeted element, or the runtime behavior of an expression. If it cannot prove a change is safe, it leaves your code alone.

<br>

## 🔬 Every transformation, before & after

### 🎯 Dot shorthands

Collapses redundant type names (enum values, static members, named constructors, and unnamed constructors (`.new`)) wherever the context type is unambiguous.

```dart
// before
final Color c = Color.blue;
Duration timeout = Duration.zero;
int port = int.parse(raw);
Service create() => Service();
Widget child(Event e) => dispatch(Event());

// after
final Color c = .blue;
Duration timeout = .zero;
int port = .parse(raw);
Service create() => .new();
Widget child(Event e) => dispatch(.new());
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

It refuses to apply when the context type is `dynamic`, `Object`, an inferred `var`, or a type variable, anywhere the shortened form would not resolve to the exact same element.

### 🔒 Private named parameters

Folds the old "public param, private field" boilerplate into a private named parameter.

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

It leaves the constructor alone when the parameter is transformed, renamed, or reused elsewhere in the initializer list.

### 🏗️ Primary constructors

Promotes a class whose only job is to bind constructor parameters to fields.

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

Skipped when the class has another constructor, a constructor body, an initializer list, or a non-`this.` parameter.

### 🔀 Switch expressions

Rewrites an eligible statement `switch` as a switch expression with modern pattern syntax: fall-through cases collapse to `||` patterns, `default` becomes `_`, and a `throw` stays inline.

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

It also handles the `return`-per-case form, producing `return switch (…) { … };`. A switch is left untouched when an arm runs more than one statement, branches assign different targets, it has side effects, or it is not exhaustive: anything where the expression form would change behavior.

### 📦 Organize imports

Sorts directives into `dart:`, `package:`, then relative groups, separates them with a blank line, and prunes the unused.

```dart
// before
import 'models.dart';
import 'dart:math';
import 'dart:convert'; // unused

// after
import 'dart:math';

import 'models.dart';
```

### 🔤 Sort members

Reorders class members into canonical order (fields, constructors, getters/setters, then methods), keeping the original order stable within each group.

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

### 🩹 Fix all

Applies the same bulk fixes as `dart fix` in the same pass: adding `@override`, dropping `new`, preferring `final` locals, and more.

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
   SDK +         full type      type safe        organize · sort
   clean         resolution     edits, in        fix · format
   analysis                     ordered passes   re-analyze
```

1. **Validate.** Reads the SDK constraint and confirms the project analyzes cleanly. Reliable resolution is what makes the rest safe.
2. **Resolve.** Loads the project with full type resolution, library by library.
3. **Transform.** Collects edits per feature using resolved types. Structural and shorthand passes run separately, with re-resolution between them.
4. **Finalize.** Organizes imports, sorts members, applies fixes, runs `dart format`, then re-analyzes to confirm zero new errors.

Run it twice and the second run changes nothing. It is **idempotent** by design.

<br>

## 🛡️ Safety

* 🔍 **Dry run first.** Produces a full diff before touching any file.
* 🚫 **Skips generated code.** Ignores `*.g.dart`, `*.freezed.dart`, and other build outputs.
* ⚖️ **Refuses ambiguity.** Will not apply a shorthand when the context type is too imprecise to guarantee an identical result.
* ✅ **Verifies after every pass.** The project must still analyze without errors.

Run on a clean working tree, review the diff, then commit with confidence.

<br>

## 🤝 Contributing

Contributions are welcome. Read `CONTRIBUTING.md`, then make sure your change passes `dart format`, `dart analyze`, and `dart test` before opening a pull request.

<br>

<div align="center">

Released under the **MIT License**.

<sub>Built with the official Dart analyzer. Type aware, behavior preserving, idempotent.</sub>

</div>

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
</table>

<div align="center"><sub>Same types. Same elements. Same behavior. Just modern.</sub></div>

<br>

## 🚀 What it does

| | Feature | Description |
|:--:|:--|:--|
| 🎯 | **Dot shorthands** | Collapses `ClassName.member` and `ClassName.new(...)` to `.member` and `.new(...)` wherever the context type makes the target unambiguous. |
| 🔒 | **Private named parameters** | Folds verbose constructor boilerplate into the modern private named parameter form. |
| 🏗️ | **Primary constructors** | Promotes eligible classes to the primary constructor form, only when it is provably safe. |
| 📦 | **Organize imports** | Sorts, groups, and prunes unused directives. |
| 🔤 | **Sort members** | Reorders members into the canonical order. |
| 🩹 | **Fix all** | Applies the same bulk fixes as `dart fix`, in the same pass. |

> Every edit is type checked before it lands. The tool **never** changes the resolved type or the targeted element of an expression. If it cannot prove a change is safe, it leaves your code alone.

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

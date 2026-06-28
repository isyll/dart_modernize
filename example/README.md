# Examples

Install the CLI:

```sh
dart pub global activate dart_modernize
```

Preview every change in the current project without writing anything:

```sh
dart_modernize --dry-run
```

Apply the changes:

```sh
dart_modernize
```

Target a folder:

```sh
dart_modernize lib/
```

Turn a pass off:

```sh
dart_modernize --no-primary-constructors
```

Run `dart_modernize --help` for the full list of options.

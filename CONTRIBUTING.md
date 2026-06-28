# Contributing

1. Fork the repo and create a branch from `main`.
2. Run `dart pub get`.
3. Make your changes: all logic goes in `lib/src/`, tests in `test/`.
4. Ensure these all pass before opening a PR:
   ```sh
   # format everything except the golden fixtures, which are kept unformatted
   dart format $(git ls-files '*.dart' ':!test/fixtures')
   dart analyze --fatal-infos
   dart test
   ```
5. Open a pull request with a clear description of what and why.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

`riff` is a Flutter application in its initial scaffold state. The entire app lives in `client/` and is currently the default Flutter counter demo (`client/lib/main.dart`). There is no server, custom architecture, or added dependencies yet — expect to build structure from scratch as features are added.

## Commands

Run all commands from the `client/` directory.

- Install deps: `flutter pub get`
- Run app: `flutter run` (add `-d chrome`, `-d windows`, etc. to target a device)
- Analyze/lint: `flutter analyze`
- Format: `dart format .`
- Test (all): `flutter test`
- Test (single file): `flutter test test/widget_test.dart`
- Test (single by name): `flutter test --plain-name "substring of test description"`
- Build release: `flutter build apk` / `flutter build windows` / `flutter build web`

## Notes

- Dart SDK constraint: `^3.12.2` (see `client/pubspec.yaml`).
- Lints come from `flutter_lints` via `client/analysis_options.yaml`; customize rules there.
- Add dependencies by editing `pubspec.yaml` then running `flutter pub get` (or `flutter pub add <pkg>`).

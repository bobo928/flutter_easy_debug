# Publishing

Before publishing a new version:

1. Update the version in pubspec.yaml and the HAR creator version in lib/src/core/log_export.dart, and move the unreleased Changelog entries to that version.
2. Verify the repository metadata and supported SDK/platform claims.
3. Run the formatting, analysis and test commands from README.md.
4. Inspect the example on supported devices, including a profile build for frame/memory checks and a release build to confirm the default disabled behavior.
5. Run the packaging check:

```sh
flutter pub publish --dry-run
```

Only publish after reviewing the archive and warnings:

```sh
flutter pub publish
```

Publishing is a separate release action. The CI workflow and a dry run do not publish the package.

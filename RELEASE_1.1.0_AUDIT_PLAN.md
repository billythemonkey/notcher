# Release 1.1.0 Audit Plan

## Issue-to-file mapping

- #2 macOS compatibility
  - `../notchprompt.xcodeproj/project.pbxproj`: deployment target + version/build settings.
  - `../scripts/check_release_compat.sh` (new): CI/local script to print project deployment target and built app minimum system version.
  - `../.github/workflows/release.yml`: run compatibility check against release build artifact path.

- #3 settings window too small / non-scrollable
  - `SettingsWindowController.swift`: reasonable default + minimum window size while allowing resize.
  - `ContentView.swift`: wrap settings content in `ScrollView` with padding so all controls remain reachable on smaller window heights.

- #4 wrong screen selected with external display
  - `ScreenSelection.swift` (new): pure display selection logic using screen descriptors.
  - `OverlayWindowController.swift`: build descriptors from `NSScreen` and delegate selection to pure function.
  - `ScreenSelectionSelfTests.swift` (new): unit-style assertions using mocked descriptors (debug-only harness).
  - `AppDelegate.swift`: run debug self-tests at launch.

- Release 1.1.0 verification
  - `../notchprompt.xcodeproj/project.pbxproj`: `MARKETING_VERSION = 1.1.0`, increment `CURRENT_PROJECT_VERSION`.
  - `../scripts/build_release_zip.sh`: existing packaging path used for DMG verification.

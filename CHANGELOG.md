# Changelog

## 1.1.0 - 2026-02-25

- Fixed macOS compatibility packaging/build settings so release artifacts advertise a minimum macOS that includes 15.7.x.
- Fixed settings usability by making the settings content scrollable and reachable at smaller window heights while keeping the window resizable.
- Fixed multi-display behavior so the overlay prefers the built-in MacBook display by default, with user-selected display override and robust fallback to menu-bar screen.
- Added release compatibility check script used in CI to print deployment target and built app minimum system version.

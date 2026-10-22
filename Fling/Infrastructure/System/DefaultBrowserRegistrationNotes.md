# Default Browser Registration Notes

This file documents the next validation step for Fling.

## Goal

Verify that the built app can be selected as the default browser and receives `http` / `https` URLs correctly on macOS.

## Notes

The current scaffold includes an AppKit app delegate entry point for `application(_:open:)`, but a Swift Package executable does not yet provide a bundled macOS app with a production `Info.plist`.

That means this scaffold is sufficient for:

- app lifecycle code,
- routing logic,
- config persistence,
- UI iteration,
- manual test URL routing through the app window.

It is **not yet sufficient** for full default-browser validation.

## Next implementation step

Move from package-only scaffold to a bundled macOS app target with verified bundle metadata for browser/default-handler registration.

At that point we should validate:

1. the app appears in macOS default browser selection,
2. clicking `http` / `https` links launches Fling,
3. `application(_:open:)` receives the URLs,
4. unmatched links can present UI after cold start.

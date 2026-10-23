# CLAUDE.md

## Project

Fling is a native macOS app that acts as a browser router / default-browser shim.

Current shape:
- SwiftUI + AppKit integration
- Xcode project generated with XcodeGen
- menu bar utility app
- routes incoming URLs by config rules
- silently dispatches matched URLs
- supports Google Chrome Incognito launch paths (explicit selector action + Option-key override heuristic)
- shows a dedicated selector panel for unmatched URLs or launch fallback cases

Project root:
- `/Users/tristan/workspace/fling`

## Build and run

Use the mise tasks instead of typing long commands directly.

### Primary commands

```bash
mise run generate
mise run build
mise run open
mise run start
mise run clean
mise run release
mise run install
```

Meaning:
- `generate` → regenerate `Fling.xcodeproj` from `project.yml`
- `build` → build the macOS app
- `open` → open the built `.app`
- `start` → clean + generate + build + open
- `clean` → remove derived build products
- `release` → build the Release configuration
- `install` → build Release, copy to `/Applications/Fling.app`, register it with LaunchServices, and launch it (this is the copy that handles clicked links)

Releases: pushing a `v*` tag runs `.github/workflows/release.yml`, which calls `Scripts/package-release.sh <version>` (universal Release build, zip + dmg + SHA256SUMS in `dist/`) and publishes a GitHub release. Ad-hoc signed unless `MACOS_DEV_CERT_*` secrets exist in the `release` environment; never notarised. `.github/workflows/ci.yml` builds Debug on pushes to main and PRs.

Debug builds use bundle id `com.tristan.fling.debug`, so they never take over as the default browser from the installed Release app (`com.tristan.fling`).

### Important rule

Whenever new Swift files or assets are added, **regenerate the project**:

```bash
mise run generate
```

If you forget, Xcode/build errors will often look like:
- type not found
- file not part of target
- new asset not available

## App bundle and generated project

Key files:
- `project.yml` — XcodeGen source of truth
- `Fling.xcodeproj` — generated artifact, can be regenerated at any time
- `AppBundle/Info.plist` — app metadata, browser URL/document handler registration
- `AppBundle/Assets.xcassets` — app icon + status/menu bar assets

## Architecture overview

### App lifecycle

Core files:
- `Fling/App/FlingApp.swift`
- `Fling/App/AppDelegate.swift`

Important behavior:
- App launches as a background/menu bar utility (`.accessory`)
- Menu bar item is the primary persistent UI entry point
- Settings opens in a dedicated AppKit window controller
- Selector opens in a dedicated AppKit floating panel
- Matched routes should **not** open Settings or any main window

### Coordinator

Core file:
- `Fling/App/AppCoordinator.swift`

Responsibilities:
- hold current config
- queue incoming URLs
- run routing decisions
- launch browsers
- own selector state (`activeSelectorContext`)
- persist changes to rules/targets/preferences

If routing behavior looks wrong, start here.

### Domain models

Core files:
- `Fling/Domain/Models/AppConfig.swift`
- `Fling/Domain/Models/BrowserTarget.swift`
- `Fling/Domain/Models/Rule.swift`

Important notes:
- `BrowserTarget` represents a configured browser destination
- Chromium-style targets may include `profile.profileDirectory`
- `Rule` supports domain and regex matching
- rules now support optional user-visible names

### Routing

Core files:
- `Fling/Domain/Routing/RoutingEngine.swift`
- `Fling/Domain/Routing/RouteDecision.swift`

Current semantics:
- if Option (⌥) is held when a URL is received, attempt Google Chrome Incognito first (bypasses normal routing + selector)
- otherwise if Shift (⇧) is held when a URL is received, skip rules and show the selector for that URL only
- otherwise rules are checked in list order and the first match wins, except that a domain rule limited to a path (e.g. `github.com/reefbarman`) beats a less specific match (longer path = more specific)
- domain rule paths match per segment and case-insensitively (`/reefbarman` matches `/reefbarman/x`, not `/reefbarmanx`)
- otherwise selector is shown

### Browser launching

Core file:
- `Fling/Infrastructure/Browsers/BrowserLauncher.swift`

Current behavior:
- normal browsers open via `NSWorkspace`
- Chromium profile targets launch via the browser executable with `--profile-directory=...`
- Google Chrome Incognito launch uses Chrome executable args (`--incognito`)

Important caveat:
- Chromium profile/incognito launching is still the riskiest runtime area
- if profile behavior is wrong, do not assume config persistence is broken — the browser may be ignoring or reinterpreting launch behavior

### Browser/profile discovery

Core file:
- `Fling/Infrastructure/System/BrowserDiscovery.swift`

Behavior:
- discovers installed browsers from a known bundle-id list
- can read Chromium `Local State` for profile discovery when available
- detection is currently used primarily for fresh target seeding and internal mapping, not as a primary visible editor control

## Windows and panels

### Settings window

Core file:
- `Fling/Infrastructure/System/SettingsWindowController.swift`

This is the authoritative settings UI presentation path.
Do not reintroduce fragile `showSettingsWindow:`-style selector hacks.

### Selector modal

Core file:
- `Fling/Infrastructure/Selector/SelectorWindowController.swift`

This must remain:
- separate from Settings
- a dedicated floating modal/panel
- reactive to coordinator state

Do **not** move selector presentation back into `SettingsView` sheets.

## UI files

- `Fling/Features/Settings/SettingsView.swift` (sidebar shell; pages are `RulesSettingsPane`, `TargetsSettingsPane`, `TestLinkSettingsPane`, `GeneralSettingsPane`, shared bits in `SettingsComponents.swift`)
- `Fling/Features/Selector/SelectorView.swift`
- `Fling/Features/Targets/TargetEditorSheet.swift`
- `Fling/Features/Rules/RuleEditorSheet.swift`
- `Fling/Features/Rules/RuleCreationSheet.swift`

### Current UX expectations

#### Target editor
Expected primary fields:
- Target Name
- Browser
- Profile directory (for Chromium targets)
- Icon (optional custom image, app icon, or Chromium profile picture; shown with a small browser badge)
- In browser picker: Main / Under More / Hidden (`isEnabled` + `showsUnderMore`)

Custom icons are rasterised to 256px PNGs in `~/Library/Application Support/Fling/Icons/` (`TargetIconStore`). They are written only on save, and unreferenced `icon-*.png` files are pruned after target saves/deletes.

Do not expose extra profile fields unless there is a strong reason.
The desired mental model is simple.

#### Rule editor
Expected primary fields:
- Rule Name
- Rule Type
- Target
- Match fields
- Enabled

Do not surface raw generated ids as the primary label in UI.

#### Selector
Expected behavior:
- dedicated small translucent panel
- large icons for configured targets
- targets marked Under More sit behind a `More` tile (key `M`) that expands a compact row
- explicit `Open in Chrome Incognito` action when Chrome is installed
- `Retry Chrome Incognito` label when the current selector context originated from force-incognito handling
- centered Add Rule button
- copy URL action
- appears for unmatched URLs or launch fallback/error cases
- when Option-force-incognito fails and Chrome is not installed, show explicit messaging in selector

## Config

Runtime config path:
- `~/Library/Application Support/Fling/config.json`

Backup example path used during resets:
- `~/Library/Application Support/Fling/config.backup-before-reset.json`

### Important config behavior

- Fresh-start path should begin from `AppConfig.empty`
- Then `ConfigStore.seededConfigIfNeeded()` may auto-seed targets
- Do not reintroduce the old hard-coded sample target/rule set as the default created config after reset

### Resetting config

Resetting live config is destructive.
If asked to reset config:
1. back up the current config first
2. reset to an empty baseline
3. rely on seeded target creation on next load

## Known project-specific pitfalls

### 1. New files not in project
If you add a new Swift file and see “type not found” even though the file exists, regenerate:

```bash
mise run generate
```

### 2. Selector visibility bugs
If unmatched URLs appear to do nothing, inspect:
- `activeSelectorContext`
- `SelectorWindowController`
- whether the selector panel is being shown/closed reactively

### 3. Chrome profile confusion
If “work” and “personal” seem reversed:
- inspect the saved config file directly
- check the actual stored `profileDirectory`
- do not trust display labels alone
- remember that Chromium discovery may be unavailable on some machines (`Local State` missing)

### 4. Dock visibility
Expected behavior:
- menu bar app by default
- Dock presence only while the Settings window is open
- `AppBundle/Info.plist` must keep `LSUIElement = true`. Without it, the SwiftUI app lifecycle promotes Fling to a Dock app whenever it handles an incoming URL, even for silently matched routes. Check with `lsappinfo info -only applicationtype -app com.tristan.fling` (`UIElement` is correct, `Foreground` means Dock).
- the selector panel never changes activation policy

If Dock presence regresses, inspect:
- `AppDelegate.swift`
- `SettingsWindowController.swift`
- `SelectorWindowController.swift`

### 5. Settings should not open on matched-route dispatch
Matched routes should dispatch silently.
Only unmatched URLs or explicit user actions should open UI.

### 6. Option-key incognito override is heuristic, not source-event truth
Fling receives URL open events without original click-event modifier metadata.
Current behavior samples `NSEvent.modifierFlags` when URL intake occurs.

Implications:
- holding Option can force Chrome Incognito dispatch and bypass routing/selector
- this is timing-based and may differ from the exact modifier state at click time

## Editing guidance

When making changes in this repo:
- prefer small, explicit AppKit controllers for window/panel lifecycle
- keep selector and settings presentation separate
- prefer direct/simple config and editor UX over clever abstractions
- keep browser/profile terminology user-facing and simple
- preserve menu bar utility behavior unless explicitly changing product direction

## Good next debugging commands

### Build
```bash
mise run build
```

### Build + open app
```bash
mise run start
```

### Inspect current persisted config
```bash
python3 - <<'PY'
import json, os
path=os.path.expanduser('~/Library/Application Support/Fling/config.json')
with open(path) as f:
    print(json.dumps(json.load(f), indent=2))
PY
```

### Inspect Chrome Local State if available
```bash
python3 - <<'PY'
import json, os
path=os.path.expanduser('~/Library/Application Support/Google Chrome/Local State')
if os.path.exists(path):
    with open(path) as f:
        data=json.load(f)
    print(json.dumps(data.get('profile', {}).get('info_cache', {}), indent=2))
else:
    print('NO_LOCAL_STATE')
PY
```

## Current product direction

The intended UX direction is:
- background/menu bar app
- fast silent routing on rule match
- small dedicated browser selector modal on no match
- simple human-editable target/rule configuration
- minimal confusing profile terminology

Keep changes aligned with that direction unless explicitly told otherwise.

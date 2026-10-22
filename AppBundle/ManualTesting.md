# Fling Manual Testing

## Built app location

After a successful debug build, the app bundle is at:

```text
build/DerivedData/Build/Products/Debug/Fling.app
```

## Launch the app

From the project root:

```bash
open build/DerivedData/Build/Products/Debug/Fling.app
```

You should see the current scaffold window with:

- config status
- configured targets and rules
- a URL routing test field

## Quick in-app routing test

Before testing default-browser behavior, verify the app logic manually:

1. Launch Fling.
2. In the URL Routing Test field, enter a URL such as:
   - `https://github.com/tristan`
   - `https://developer.apple.com/documentation`
   - `https://example.com`
3. Click **Route Test URL**.
4. Confirm the **Last Route Decision** panel shows:
   - Chrome Work for `github.com`
   - Safari for matching Apple docs regex
   - selector fallback for URLs with no rule

## Set Fling as default browser

### Option 1: System Settings

1. Open **System Settings**.
2. Go to **Desktop & Dock**.
3. Find **Default web browser**.
4. Select **Fling**.

If Fling does not appear immediately:

- make sure the app has been launched once,
- rebuild once if needed,
- quit and reopen System Settings.

### Option 2: Use macOS link opening after launch registration

After launching the app at least once, macOS Launch Services should know about it. If it still does not appear, log out/in or relaunch Finder/System Settings.

## Test URL delivery from macOS

After Fling is the default browser:

### Finder / Terminal test

Run:

```bash
open 'https://github.com/tristan'
```

Expected behavior in the current scaffold:

- Fling receives the URL
- the app window updates its **Last Route Decision** panel
- for matching rules, you should see the resolved target
- for no-match URLs, you should currently see a selector decision placeholder in the UI

### Multi-link queue test

Run these quickly one after another:

```bash
open 'https://github.com/tristan'
open 'https://developer.apple.com/documentation/swiftui'
open 'https://example.com'
```

Expected behavior:

- requests queue inside the app
- one decision is shown at a time
- use **Acknowledge Decision** to advance through queued URLs

## Config file location

The app writes its config here:

```text
~/Library/Application Support/Fling/config.json
```

You can also use the **Reveal Config in Finder** button from the app.

## Current limitations of this build

- It does not yet launch Safari or Chrome.
- It does not yet show the real browser selector modal.
- It currently displays route decisions inside the main app window as a test harness.
- Browser/profile launching and polished URL handler UX are the next implementation step.

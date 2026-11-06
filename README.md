# Kakeibo

A personal budget tracker for iPhone, built for life in Japan: yen, several cards, card bills with
closing and payment days, and splitting shared costs with a partner. Everything is stored on the phone.
The app has no bank logins and no scraping.

The full set of design decisions is in [docs/DESIGN.md](docs/DESIGN.md).

## Installing on your iPhone (free Apple ID + iLoader on Windows)

The app is built in the cloud by GitHub Actions, so no Mac or Xcode is needed. It's installed from a
Windows PC with iLoader and a free Apple ID, which means a refresh
every 7 days.

### One-time setup

1. **Turn on Developer Mode** on the iPhone: Settings → Privacy & Security → Developer Mode → On.
   The iPhone restarts.
2. **Install iLoader** on the PC, connect the iPhone with a cable, and trust the computer on the iPhone.
3. Sign in to iLoader with your Apple ID.
4. After the first install, open Settings → General → VPN & Device Management on the iPhone and trust your Apple ID.

### Installing or updating Kakeibo

1. Open the repo on GitHub → **Actions** → the latest green **CI** run → download the **Kakeibo-ipa** artifact.
   It downloads as a `.zip`; unzip it to get `Kakeibo.ipa`.
2. In iLoader, choose the option to install an IPA and pick `Kakeibo.ipa`.

Installing a new build over the old one **keeps all your data**, as long as it's signed with the same
Apple ID (same bundle ID, same app). The CI run also has a **screenshots** artifact showing every screen with demo data.

### Every 7 days

Free Apple ID apps expire after 7 days. Re-install (or refresh) Kakeibo from iLoader before then. If you
miss it, the app won't open until you do. **Your data is not deleted.** You lose data only if you delete
the app, or sign in with a different Apple ID (that installs it as a different app). For safety, use
Settings → Export full backup (JSON) now and then.

A free Apple ID allows only 3 sideloaded apps at a time and a limited number of new app IDs per week.

### After installing

- **Widget:** long-press the Home Screen or Lock Screen → Edit → add the Kakeibo widget. Tapping it opens the add screen.
  The widget reads its numbers through an App Group. If it only ever shows placeholder numbers, the installer
  didn't keep the App Group when re-signing; the app itself is unaffected.
- **Control Center / Action Button:** add the "Add Kakeibo entry" control.
- **Shortcuts:** "Add Kakeibo Entry" opens the add screen. "Log Payment" (amount, merchant, card) saves an
  expense without opening the app and marks it for review. It's ready for a Wallet transaction
  automation, which we haven't tested on Japanese cards yet.

## Development

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open Kakeibo.xcodeproj
```

You don't need a Mac for this: CI (`.github/workflows/ci.yml`) generates the project, runs the unit tests in
the iOS simulator, screenshots every screen in demo mode (`scripts/screenshots.sh`, `Kakeibo/App/DemoMode.swift`),
and builds `Kakeibo.ipa` with `scripts/build-ipa.sh` on every push.

Layout:

- `Kakeibo/Models`: SwiftData models (`Account`, `BudgetCategory`, `Entry`) and the seed data.
- `Kakeibo/Logic`: balances and spending (`Ledger`), card bills (`Billing`), charts and budget lists
  (`Insights`), account order and grouping (`AccountLayout`), backup, notifications.
- `Kakeibo/Views`: SwiftUI screens.
- `Kakeibo/Intents`: the Log Payment intent and Siri/Shortcuts phrases.
- `KakeiboWidget`: the Home/Lock Screen widget and the Control Center button.
- `Shared`: code compiled into both the app and the widget.
- `KakeiboTests`: unit tests.

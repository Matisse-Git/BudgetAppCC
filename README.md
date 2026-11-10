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
Apple ID (same bundle ID, same app).

### Every 7 days

Free Apple ID apps expire after 7 days. Re-install (or refresh) Kakeibo from iLoader before then. If you
miss it, the app won't open until you do. **Your data is not deleted.** You lose data only if you delete
the app, or sign in with a different Apple ID (that installs it as a different app). For safety, use
Settings → Export full backup (JSON) now and then.

A free Apple ID allows only 3 sideloaded apps at a time and a limited number of new app IDs per week.

### After installing

- **Widgets:** long-press the Home Screen or Lock Screen → Edit → add the Kakeibo **Budget** widget (small, medium
  or Lock Screen), the **Next card bill** widget or the **Balances** widget (small or medium). Tapping
  Budget or Next card bill opens the add screen.
  - Balances shows up to four accounts. Touch and hold it → Edit Widget to choose which and in what order;
    each widget keeps its own list. On the medium size, tapping an account opens it.
  - Settings → "Hide widget amounts when locked" blanks the numbers while the iPhone is locked.
  The widgets read their numbers through an App Group, which iLoader registers for your Apple ID
  (`group.com.matisse.kakeibo.<team ID>`); Kakeibo finds it in the signing profile. If a widget only ever
  shows placeholder numbers, open Kakeibo once; if that doesn't help, the App Group isn't shared. The app
  itself is unaffected.
- **Quick entries:** set up your usual purchases (e.g. breakfast, ¥480 at Lawson) in Settings › Quick entries,
  or edit an expense and choose ⋯ › Save as Quick Entry. They show as chips in Quick Add and in the
  **Quick entries** widget, which you can add to the Home Screen or the swipe-right screen (small, medium or
  large). A tap on the widget logs the purchase: it shows ✓ and "today ×N", and the entry lands in your
  totals the next time you open Kakeibo. If the widget stays empty after you've added quick entries, the
  App Group isn't shared (see Widgets above).
- **Control Center / Action Button:** add the "Log Expense" control.
- **Shortcuts:** "Add Kakeibo Entry" opens the add screen. "Log Quick Entry" saves one of your quick entries
  without opening the app. "Log Payment" (amount, merchant, card) saves an
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
the iOS simulator and builds `Kakeibo.ipa` with `scripts/build-ipa.sh` on every push.

Layout:

- `Kakeibo/Models`: SwiftData models (`Account`, `BudgetCategory`, `Entry`, `QuickEntry`) and the seed data.
- `Kakeibo/Logic`: balances and spending (`Ledger`), card bills and holiday shifts (`Billing`,
  `JapaneseHolidays`), budget pace and trends (`Insights`), account forecasts and card history
  (`AccountInsights`), add-sheet suggestions (`Suggestions`), account order and grouping (`AccountLayout`),
  quick entries and widget taps (`QuickEntries`), backup, notifications (`Maintenance`).
- `Kakeibo/Views`: SwiftUI screens, built on the shared components in `DesignComponents.swift`.
- `Shared/DesignTokens.swift`: colours, type and sizes from the design canvas (see CLAUDE.md).
- `Kakeibo/Intents`: the Log Payment and Log Quick Entry intents and Siri/Shortcuts phrases.
- `KakeiboWidget`: the Budget, Next card bill, Balances and Quick entries widgets and the Control Center button.
- `Shared`: code compiled into both the app and the widget.
- `KakeiboTests`: unit tests.

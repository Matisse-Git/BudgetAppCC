# Kakeibo

A personal budget tracker for iPhone, built for life in Japan: yen, several cards, card bills with
closing and payment days, and splitting shared costs with a partner. Everything is stored on the phone.
The app has no bank logins and no scraping.

The full set of design decisions is in [docs/DESIGN.md](docs/DESIGN.md).

## Installing on your iPhone (free Apple ID + AltStore)

The app is built in the cloud by GitHub Actions, so you don't need Xcode on your Mac.

### One-time setup

1. **Turn on Developer Mode** on the iPhone: Settings → Privacy & Security → Developer Mode → On.
   The iPhone will restart.
2. **Install AltServer** on your Mac from [altstore.io](https://altstore.io). It sits in the menu bar.
3. Connect the iPhone to the Mac with a cable, then choose AltServer → Install AltStore → your iPhone.
   Sign in with your Apple ID when asked.
4. On the iPhone, open Settings → General → VPN & Device Management and trust your Apple ID.
5. In AltServer, enable "Mail plug-in" if it asks (macOS needs this for AltServer to sign apps).

### Installing or updating Kakeibo

1. Open the repo on GitHub → **Actions** → the latest green **CI** run → download the **Kakeibo-ipa** artifact.
   It downloads as a `.zip`; unzip it to get `Kakeibo.ipa`.
2. Install it in either of these ways:
   - **On the iPhone:** save `Kakeibo.ipa` to Files, open AltStore → My Apps → **+** → pick the file.
   - **From the Mac:** hold ⌥ Option, click the AltServer menu-bar icon, choose **Sideload .ipa…**, and pick the file.

Installing a new build over the old one **keeps all your data**.

### Every 7 days

Free Apple ID apps expire after 7 days. Open AltStore → My Apps → **Refresh All** while the iPhone is on the
same Wi-Fi as the Mac and AltServer is running. AltStore also refreshes in the background when it can.

If you miss a week, the app won't open until you refresh it. **Your data is not deleted.** You lose
data only if you delete the app, or sign AltStore into a different Apple ID (that installs it as a
different app). For safety, use Settings → Export full backup (JSON) now and then.

A free Apple ID allows 3 sideloaded apps at a time: AltStore, Kakeibo and Kakeibo's widget.

### After installing

- **Widget:** long-press the Home Screen or Lock Screen → Edit → add the Kakeibo widget. Tapping it opens the add screen.
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

CI (`.github/workflows/ci.yml`) generates the project, runs the unit tests in the iOS simulator, and builds
`Kakeibo.ipa` with `scripts/build-ipa.sh` on every push.

Layout:

- `Kakeibo/Models`: SwiftData models (`Account`, `BudgetCategory`, `Entry`) and the seed data.
- `Kakeibo/Logic`: balances and spending (`Ledger`), card bills (`Billing`), backup, notifications.
- `Kakeibo/Views`: SwiftUI screens.
- `Kakeibo/Intents`: the Log Payment intent and Siri/Shortcuts phrases.
- `KakeiboWidget`: the Home/Lock Screen widget and the Control Center button.
- `Shared`: code compiled into both the app and the widget.
- `KakeiboTests`: unit tests.

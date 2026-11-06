# Kakeibo: notes for working on this repo

Personal budget tracker for iPhone (SwiftUI + SwiftData, iOS 18+), built for yen and life in Japan.
Product decisions live in [docs/DESIGN.md](docs/DESIGN.md); update it when a decision changes.
The visual spec is the Claude Design canvas "Kakeibo"
(https://claude.ai/code/artifact/c43604f3-7918-4c6f-bac6-0f1cb6e49855). Treat its HTML as a visual and
behavioural spec, not code to port.

## Building and testing

- There is no Mac. CI (`.github/workflows/ci.yml`, macOS runner) generates the project with XcodeGen,
  runs `KakeiboTests` in the simulator, screenshots every screen in demo mode and builds the IPA.
  Push, then read the CI run: it is the compiler. Cloud sessions have no Swift toolchain.
- Demo mode: launch with `-demo -screen <name>` (`Kakeibo/App/DemoMode.swift`); `scripts/screenshots.sh`
  lists the screens. Add new screens there so CI screenshots them.
- New source files are picked up automatically (`project.yml` lists folders, not files). `Shared/` is
  compiled into both the app and the widget.

## Architecture

- No view-model classes. Views read `@Query` and derive everything through plain value types in
  `Kakeibo/Logic` (`Ledger`, `MonthSummary`, `Billing`, `BudgetListing`, `AccountLayout`). Put new
  calculations there and cover them in `KakeiboTests`.
- SwiftData changes are additive only: new stored properties with defaults, never renamed or removed.
  Records link by UUID, not relationships. Mirror new fields in `Backup` as optionals so old backups
  still restore. Preferences that aren't data go in `UserDefaults` under `SettingsKey`.
- Haptics follow the table in docs/DESIGN.md (`Haptics` in `Components.swift`).

## Design tokens

Defined in `Shared/DesignTokens.swift` (`Palette`, `Hue`, `CardColor`, `Metrics`, `Font.k…`). Never
hard-code a colour or size in a view; add a token instead and record it here. Dark values are the
canvas's; the canvas is dark-only, so light values are derived (iOS light equivalents, darkened where
needed so text keeps 4.5:1 on its surface).

### Colour

| Token | Dark (canvas) | Light | Use |
| --- | --- | --- | --- |
| `Palette.background` | `#000000` | `#F2F2F7` | Screen background |
| `Palette.card` | `#1C1C1E` | `#FFFFFF` | Cards on a screen |
| `Palette.sheet` | `#1C1C1E` | `#F2F2F7` | Sheet background |
| `Palette.sheetRow` | `#2C2C2E` | `#FFFFFF` | Grouped rows inside a sheet |
| `Palette.controlFill` | `#767680` 24% | `#767680` 12% | Keys, secondary buttons, segmented track |
| `Palette.chipFill` | `#767680` 20% | `#767680` 12% | Chips in the add sheet |
| `Palette.track` | `#767680` 30% | `#767680` 16% | Empty part of bars |
| `Palette.separator` | `#545458` 42% | `#3C3C43` 22% | Row dividers |
| `Palette.segmentSelected` | `#636366` | `#FFFFFF` | Selected segment |
| `Palette.tabSelection` | white 11% | black 6% | Selected tab pill |
| `Palette.toast` | `#3A3A3E` 97% | white 98% | Undo toast |
| `Palette.textPrimary` | `#FFFFFF` | `#000000` | Text |
| `Palette.textSecondary` | `#98989F` | `#6E6E73` | Secondary text |
| `Palette.textTertiary` | `#6E6E73` | `#AEAEB2` | Chevrons |
| `Palette.accentFill` | `#5E5CE6` | `#5E5CE6` | The one prominent action per surface (white text) |
| `Palette.accentTint` | `#8A87FF` | `#5856D6` | Links, icons; also `AccentColor` in the asset catalog |
| `Palette.accentData` | `#7D7AFF` | `#5E5CE6` | Charts, overall budget bar |
| `Palette.accentSoftFill` / `accentSoftText` | `#8A87FF` 20% / `#A9A7FF` | `#5856D6` 14% / `#4B49C4` | "Auto" badge, Undo, Back Up Now |
| `Palette.positive` | `#30D158` | `#1F7A35` | Income, on track, covered |
| `Palette.negative` | `#FF453A` | `#FF3B30` | Over budget, delete (fills) |
| `Palette.negativeText` | `#FF6961` | `#D70015` | Over budget (text) |
| `Palette.warning` | `#FF9F0A` | `#C93400` | Shortfall, at risk, spent more |
| `Palette.info` | `#409CFF` | `#0A64D6` | Spent less |
| `Palette.paceTick` | `#FFFFFF` | `#000000` | Today's pace tick on budget bars |

Category/account hues (`Hue`, tile fill = hue at 16–20%): green `#30D158`, orange `#FF9F0A`,
tan `#C9A27E`, blue `#409CFF`, purple `#BF5AF2`, pink `#FF375F`, mint `#63E6E2`, yellow `#FFD60A`,
cyan `#64D2FF`, gray `#AEAEB2`, teal `#40C8E0`, indigo `#7D7AFF` (dark values; light ones are darker).

Card colours (`CardColor`, same in both modes): Blue `#3D52D5`, Teal `#0F7B6C`, Raspberry `#B8325A`,
Amber `#B9651B`, Violet `#6B4FBB`, Graphite `#48484A`. Each has a `bright` variant for bars on dark.

### Type

SF Pro with Dynamic Type. Amounts always use `.monospacedDigit()`; yen never shows decimals. Spending
shows without a sign, income as `+¥318,400` in green, account histories use a true minus `−¥20,000`
(`Yen.format`).

| Role | Spec | SwiftUI |
| --- | --- | --- |
| Amount entry | 64 Bold, tracking −2; `¥` 34 Semibold secondary | `.kAmountEntry`, `.kAmountCurrency` |
| Hero amount | 44 Bold, tracking −1.2 | `.kHero` |
| Detail amount | 40 Bold, tracking −1 | `.kDetailAmount` |
| Card statistic | 34 Bold, tracking −0.8 | `.kStat` |
| Large Title | 34 Bold | `.largeTitle.bold()` |
| Title 3 | 20 Bold (section titles) | `.title3.bold()` |
| Headline | 17 Semibold | `.headline` |
| Body | 17 Regular (row titles 17 Medium) | `.body` |
| Subheadline | 15 | `.subheadline` |
| Footnote | 13 | `.footnote` |
| Section caps | 13 Semibold, uppercase, tracking 0.2 | `.kSectionCaps` (`SectionCaps`) |
| Tab label | 10 Semibold | `.kTabLabel` |

### Layout

`Metrics`: 16 pt gutter, 24 pt card radius (22 for grouped rows in sheets), 16 pt card padding, 28 pt
between sections, 62 pt rows (50 compact), 32 pt row icons (square r = 0.28 × size for categories,
circle for accounts, 36 × 24 mini card for credit cards), 44 pt buttons, 58 pt keypad keys (r 16, 8 gap),
62 pt tab bar.

### SF Symbols

Categories (matched by name in `CategoryLook`, synonyms included): Groceries `cart.fill`, Dining Out
`fork.knife`, Café & Snacks `cup.and.saucer.fill`, Transport `tram.fill`, Shopping `bag.fill`,
Entertainment `ticket.fill`, Health & Beauty `heart.fill`, Utilities `bolt.fill`, Phone & Internet
`wifi`, Subscriptions `repeat`, Rent `house.fill`, Other `square.grid.2x2.fill`, Salary `yensign`,
Bonus `star.fill`, Side income `briefcase.fill`, Refund `arrow.uturn.backward`, gifts `gift.fill`.
Unknown categories keep their emoji and get a stable hue from their name.

Accounts (`AccountLook`): Bank `building.columns.fill`, Transit IC `wave.3.right`, QR Pay `qrcode`,
other top-ups `wallet.pass.fill`, Cash `banknote.fill`; credit cards are a mini card.

Tabs: Summary `house`, Activity `list.bullet`, Budgets `chart.pie`, Accounts `creditcard`.

### Components (`Kakeibo/Views/DesignComponents.swift`, `TabBar.swift`)

`kCard()`, `CardList` + `ListDivider`, `KRow`, `AmountStack`, `Chevron`, `CategoryIcon`, `SymbolTile`,
`AccountIcon`, `MiniCard`, `SectionTitle`, `SectionCaps`, `BudgetBar` (fill + pace tick, red past
100%), `StatusChip`, `AutoBadge`, `PillButtonStyle` (`.pill`, `.pillSecondary`), `UndoToast`,
`GlassBackground` (glass on iOS 26, material before), `KakeiboTabBar`.
Navigation bars are the system ones (glass back and Edit buttons on iOS 26).

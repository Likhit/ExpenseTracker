# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cross-platform (Android, Linux) double-entry bookkeeping app for personal finance. Tracks incomes, expenses, and investments. No web server — data stored as append-only JSONL files synced via Google Drive or OneDrive (user picks a local sync folder).

**Framework**: Flutter (Dart) | **State management**: Riverpod | **Models**: freezed + json_serializable

## Dev Environment

NixOS-based. The project is a Nix flake with direnv (`.envrc` → `use flake`). Entering the project directory auto-loads the dev shell with Flutter SDK, Dart, and Linux build dependencies.

### Workflow
After completing each implementation phase:
1. Run `flutter test` and `flutter analyze`
2. Create a commit
3. Send a PR (one PR per phase; user reviews each before the next phase starts)

### Commands
- `flutter run -d linux` — run Linux desktop app
- `flutter build linux` — release build
- `flutter test` — unit + widget tests
- `flutter test integration_test/` — integration tests (needs running emulator or Linux desktop)
- `flutter analyze` — static analysis
- `flutter pub run build_runner build --delete-conflicting-outputs` — regenerate freezed/json_serializable code (use `flutter pub run`, not `dart run`, since the dev shell needs Flutter)

## Architecture

```
lib/
  main.dart
  app.dart                          # MaterialApp, theme, routing

  models/                           # freezed data classes + value types
    account.dart                    # Account + built-in expenseId/incomeId
    category.dart
    currency.dart
    transaction.dart                # includes Transaction.validate()
    leg.dart
    ids.dart                        # extension types for every Id
    line_id.dart                    # sealed LineId { first | of(uuid) }
    path_helper.dart                # PathHelper mixin + CategoryPath ext
    validation_result.dart          # ValidationResult + Validatable iface

  data/                             # data layer
    storage/
      jsonl_store.dart              # generic JSONL read/append/writeAll
      jsonl_storable.dart           # JsonlEntity + JsonlStorable<Id> ifaces
      file_sync.dart                # conflict detection & merge (Phase 1.9)
    repositories/
      repository.dart               # generic Repository + ReadOnlyRepository
      account_repository.dart       # trivial typed subclass
      category_repository.dart
      transaction_repository.dart
      currency_repository.dart

  services/                         # business logic
    ledger_service.dart             # the single entry point
    query/
      ledger_filter.dart            # filter spec
      ledger_group.dart             # group dimensions + sealed GroupKey
      ledger_stats.dart             # Stats container + sealed QueryResult
      stat.dart                     # Stat<V> functor + built-ins

  ui/                               # see "UX Specification" below
    screens/
    widgets/

  providers/                        # Riverpod providers
```

### Key Dependencies
- `flutter_riverpod` — state management
- `freezed` + `json_serializable` — typed immutable models with JSON serialization
- `uuid` — entity IDs and per-append `lineId`s
- `decimal` — precise money arithmetic (no floating point)
- `fl_chart` — charts for reports
- `file_picker` — sync folder selection
- `path_provider` — app data directories
- `intl` — date/number formatting
- `fuzzy` or similar — fuzzy search for category path input
- `sembast` — Phase 1.8/C, persistent KV cache for pre-computed views

## Engine Conventions

### LedgerService — the single entry point
The `LedgerService` owns the four append-only JSONL repositories and is the *only* surface for engine consumers (Riverpod providers, UI, tests). Repositories are private fields; external callers get read-only access through:

```dart
ledger.accounts      // ReadOnlyRepository<AccountId, Account>
ledger.categories    // ReadOnlyRepository<CategoryId, Category>
ledger.currencies    // ReadOnlyRepository<CurrencyId, Currency>
ledger.transactions  // ReadOnlyRepository<TransactionId, Transaction>
```

All writes go through generic helpers — `ledger.save<T>(entity)`, `ledger.saveAll<T>(entities)`, `ledger.delete<T>(entity)` — which validate (when the entity implements `Validatable`) and dispatch to the right repo based on the entity's runtime type.

### Construction
**Construction is async**, via `LedgerService.create(...)`. The factory ensures the built-in Expense and Income accounts exist on disk before returning. Direct construction is private — there is no synchronous path.

```dart
final ledger = await LedgerService.create(
  accountsPath: '...',
  categoriesPath: '...',
  currenciesPath: '...',
  transactionsPath: '...',
);
```

### Repositories
- `Repository<Id, T extends JsonlStorable<Id>>` is the generic base.
- `streamAll()` returns the latest version of every entity (dedup by id, newest-first) as a `Stream<T>`. `getAll()` is just `streamAll().toList()`.
- `save` / `saveAll` / `delete` assign chain pointers automatically (see "Append-chain" below). Callers never set `lineId` or `prev` manually.
- The repository class is internal to `LedgerService`; production code shouldn't touch it directly.

### Append-chain (per-file)
Every saved entity carries `lineId` and `prev`:

- **`LineId`** is a sealed type with two variants:
  - `LineId.first()` — sentinel for "no previous append"
  - `LineId.of(String uuid)` — a real UUID generated by the repo per write
- **`lineId`** is `LineId?` on the entity (null for unsaved); always non-null once persisted.
- **`prev`** is non-nullable; defaults to `LineId.first()`. The repo overwrites it on save.

The chain is **per-file, not per-entity**: each save's `prev` points to whatever the file's previous append was, regardless of entity id. A repo file is therefore a single linear chain of every append it ever received. Phase 1.9 sync uses this chain to rebase divergent files.

### Stats / query architecture
See `services/query/` for the filter/group/stats engine.

- **`LedgerFilter`** — optional include/exclude constraints on accounts, currencies, categories, plus tx-level date range, types, and includeDeleted. Category match is segment-aware: `Food` matches `Food::Groceries` but not `Foodie`.
- **`GroupDimension`** — sealed: `byAccount`, `byCategory({depth})`, `byCurrency`, `byTime(TimeBucket)`. Compose by passing a list to `query`.
- **`GroupKey`** — one variant per dimension, plus `none()` for legs missing the dimension (e.g., a Chase leg with no categoryPath under `byCategory`) and for the root of every result tree.
- **`Stat<V>`** — incrementally maintainable functor: `value`, `apply(leg, tx)`, `combine(other)`. **Apply respects `tx.deleted` as its sign** — a deleted leg contributes the *negative* of an active one. That single convention covers both one-shot aggregation and the "revert by re-applying with deleted flipped" incremental path. Built-ins: `CountStat`, `SumByCurrencyStat`.
- **`Stats`** — typed container of `Stat`s (`Map<Type, Stat>`). `Stats.of([...])` for a custom template; `Stats.defaults()` for count + sumByCurrency. Convenience getters `stats.count` and `stats.sumByCurrency`.
- **`QueryResult`** — sealed: `LeafResult { key, transactions, stats }` and `NodeResult { key, children, stats }`. `stats` is computed eagerly at build time and stored on every node (rolled up via `combine`). `transactions` and `children` are exposed via an extension on `QueryResult` that returns `Iterable` — leaf returns its stored value, node returns a lazy walk (no materialization until iteration).

### Query semantics
`ledger.query(filter, {groupBy})`:
1. Streams the transaction repo lazily, never materializing the full journal.
2. For each transaction, asks `filter` for its surviving legs. Non-matching legs are discarded immediately.
3. Builds the `QueryResult` tree. With no `groupBy`, the result is a single `LeafResult(key: none, …)`. With grouping, the root is a `NodeResult(key: none, children: …)` whose leaves are partitioned per dimension.
4. **Filtering is at the leg level; transactions are deduplicated at the leaf.** A transfer touching account A and B matches an A-filter via the A-leg only; the B-leg doesn't contribute to stats. Both the parent transaction (returned once in `transactions`) and the matched leg's amount (folded into `stats`) appear in the result.

`ledger.computeBalances()` is implemented on top of `query` with `groupBy: [byAccount, byCurrency]`.

## Data Model

### Double-Entry Bookkeeping
Every transaction is a journal entry with 2+ legs (debit/credit). The UI is simplified (user picks category + account), but the data model is full double-entry.

**Account types**: `asset, liability, income, expense, equity`. The `income` and `expense` types are **reserved for two built-in accounts**:

- `Account.expenseId` — the singleton Expense account (path: `Expense`)
- `Account.incomeId` — the singleton Income account (path: `Income`)

These are guaranteed to exist by `LedgerService.create`. **Users never create or delete them.** They're pure external balancing sinks/sources for the double-entry invariant.

**Invariant**: For same-currency transactions, sum of all legs = 0. For cross-currency transfers, the exchange is recorded in `metadata.exchangeRate`.

**Category placement rule**: The built-in Expense and Income accounts must **not** carry a `categoryPath`. Category lives on the *asset-side leg* — the leg whose account is the user's real asset/liability (Chase, Fidelity, credit card, …). `Transaction.validate()` enforces this.

### Entities

**Currency**: `id, code (USD/EUR/AAPL/BTC), name, type (fiat/stock/crypto), symbol?, decimalPlaces`

**Account** (hierarchical, manually created by user — except the two built-ins): `id, path (Chase::Checking), type, isVirtual, notes?, createdAt, updatedAt?, deleted, lineId?, prev`
- `::` separator, shallow depth (1-2 levels typical)
- Grouped in UI by shared root segment
- Balances computed per-currency from transactions

**Category** (hierarchical, dynamically created on the fly): `id, path (Food::Snacks::Cake), parentType (income/expense), icon?, color?, createdAt, updatedAt?, deleted, lineId?, prev`
- `::` separator, arbitrary depth
- Created on-the-fly during transaction entry
- Root categories shown as grid; deeper paths via fuzzy search
- Icon/color set on root categories, inherited by children

**Transaction** (Journal Entry): `id, date, description, type (expense/income/transfer), legs[], metadata?, createdAt, updatedAt?, deleted, lineId?, prev`

**Leg**: `accountId, amount (positive=debit, negative=credit), currencyCode, categoryPath?`

### Double-Entry Examples

Simple expense ($50 groceries):
```
Leg 1: Credit Assets::Chase::Checking  -50.00 USD  (category: Food::Groceries)
Leg 2: Debit  Account.expenseId        +50.00 USD
```
The Chase leg carries the category; the Expense leg is the bare balancing sink.

Income ($1000 salary):
```
Leg 1: Credit Account.incomeId         -1000.00 USD
Leg 2: Debit  Assets::Chase::Checking  +1000.00 USD  (category: Salary)
```
The Chase leg carries the category; the Income leg is the bare balancing source.

Cross-currency transfer (10 AAPL at $200):
```
Leg 1: Credit Assets::Chase::Checking  -2000.00 USD
Leg 2: Debit  Assets::Fidelity         +10.00 AAPL
metadata: { exchangeRate: { from: "USD", to: "AAPL", rate: 0.005, inverse: 200.0 } }
```
No category on either side (transfer between user-owned accounts).

## File Format

Append-only JSONL, split by type: `transactions.jsonl`, `accounts.jsonl`, `categories.jsonl`, `currencies.jsonl`

Edits and deletes append a new line with the same UUID and a newer `updatedAt`. State is reconstructed by keeping only the latest version per UUID. No compaction — if storage becomes an issue, migrate to a dedicated DB.

Every line carries `lineId` (sealed `LineId.of(uuid)` once persisted) and `prev` (`LineId.first` or `LineId.of(uuid)` — the file's previous tip). Files are therefore self-describing chains.

### Conflict Resolution (Phase 1.9)
On startup, scan sync folder for conflict copies (e.g., `transactions (1).jsonl`). Per-entity merge: detect divergence on shared entities, rebase via `prev`-pointer rewrite. On rebase tie, surface a `LedgerState.Conflicted` (with `EntityConflict` list) and reject further writes until `ledger.resolveConflicts(resolution)` is called. Delete conflict copies after successful merge.

## Testing Strategy

### Layer 1: Unit Tests
- Data models, repositories, services (ledger validation, balance computation, query engine, Stat contracts)
- Pure Dart, no Flutter dependencies needed for most
- `flutter test test/`
- **Generic Repository tests use a hand-written `TestEntity`** (`test/data/repositories/test_entity.dart`) — don't reuse production model classes to test the repository contract.

### Layer 2: Widget Tests (headless, no emulator)
- Test every screen, form, picker, and interaction at the widget level
- Runs in Dart VM — fast (~100ms/test), zero setup
- Catches 80%+ of UI bugs
- `flutter test test/`

### Layer 3: Golden Tests (headless, no emulator)
- Screenshot comparison for key screens (dashboard, transaction form, reports)
- Catches visual regressions
- Baseline images are platform-specific, stored in repo
- `flutter test --update-goldens` to regenerate baselines

### Layer 4: Integration Tests (headless emulator)
- Full app E2E: file I/O, JSONL persistence, complete user journeys
- Run with headless Android emulator (`emulator -avd <name> -no-window`) or Linux desktop
- 10-20 critical path scenarios
- `flutter test integration_test/`
- Requires KVM on Linux for Android emulator

## UX Specification (for design / wireframing in parallel)

This section is the source of truth for the UI design work that can happen alongside engine development. It specifies the platforms, IA, screen inventory, navigation, and per-screen content so wireframes can be drafted before Phase 2 implementation begins.

### Platforms & form factors
- **Mobile (Android)**: Material 3, portrait-first. Bottom navigation. FAB for "add transaction".
- **Desktop (Linux)**: Material 3 for v0; a swappable theme layer is planned (KDE/GTK) but deferred. Sidebar/drawer navigation. Keyboard shortcuts for save/cancel.
- Both platforms render the same screens from a shared widget tree. Density, padding, and nav chrome adapt to width breakpoints.

### Information architecture
Top-level destinations (bottom nav on mobile, sidebar on desktop):

1. **Home** — dashboard with summary cards
2. **Transactions** — list + filters; "+" FAB opens entry flow
3. **Accounts** — list + balances
4. **Reports** — charts and breakdowns
5. **Settings** — sync, currencies, theme, defaults

Secondary destinations reached from the above:
- Categories list (from Settings or accessible via Add Transaction flow)
- Currencies list (from Settings)
- Transaction details / edit (from Transactions list)
- Account details (from Accounts list)
- Per-report drill-down (from Reports)

### First-launch flow
1. **Welcome** — short value proposition, "Continue" button.
2. **Sync folder picker** — "Choose sync folder" (file picker) or "Set up later (local-only)". Explains what the folder is for.
3. **Currency setup** — pre-seeded list of common currencies (USD, EUR, GBP, INR, JPY, BTC, ETH). User can toggle which to enable and pick a default. "Add custom currency" available for stock tickers.
4. **First account** — prompt to create a starter account (defaults: name "Checking", type Asset, default currency). The built-in Expense and Income accounts already exist (auto-created by `LedgerService.create`) and don't appear in this step.
5. **Land on Home dashboard**.

Onboarding can be skipped — defaults are reasonable and the user can complete setup in Settings.

### Add Transaction flow
The "+" FAB opens a chooser with three tiles: **Expense**, **Income**, **Transfer**.

#### Expense flow (matches the data model — category on the asset-side leg)
1. **Amount + Currency** — large numeric input, currency picker defaults to the account's primary currency, then to last used.
2. **Category** — root categories shown as an icon grid (Food, Transport, Bills, Shopping, …). Typing in a search box runs fuzzy search across all known `Food::Snacks::Cake`-style paths. Typing a new `::` path creates the category on the fly (with optional icon/color prompt for new roots).
3. **Account** (the asset/liability the money is coming out of) — defaults to last used; grouped by root segment (Chase, Citi, Cash, …). Picker shows current balance per account as a hint.
4. **Description** (optional) — single line.
5. **Date** — defaults to today; pill chips for "Today / Yesterday / Pick…".
6. **Save** — appends a 2-leg transaction: the chosen asset account (negative amount, category attached) and the built-in Expense account (positive amount, no category).

#### Income flow
Same shape as Expense, but step 3 is the *destination* account (where the money lands) and step 2's categories come from the Income hierarchy (Salary, Refund, Gift, …). Saves a 2-leg transaction: built-in Income account (negative) and the destination account (positive, category attached).

#### Transfer flow
1. **From account** — picker (asset/liability).
2. **To account** — picker (asset/liability).
3. **Amount** — single field if both accounts share a currency; *two* fields if they differ (with the exchange rate computed and displayed live, editable).
4. **Description** (optional).
5. **Date** — defaults to today.
6. **Save** — appends a 2-leg transaction with both legs being asset accounts; cross-currency transfers include `metadata.exchangeRate`.

### Screen-by-screen content

#### Home dashboard
- **Header**: greeting + total net worth (sum of asset balances in the default currency, with per-currency breakdown on tap).
- **Summary cards** (this month, current period configurable in Settings):
  - Income (positive number, with last-month delta).
  - Expenses (negative number, with last-month delta).
  - Net cash flow (income − expenses).
- **Top accounts** — 3–5 highest-balance asset accounts, with sparkline or just current balance per currency.
- **Recent transactions strip** — last 5 transactions; tap → transaction details.
- **Quick add** — small icon row that jumps to Expense/Income/Transfer with one tap.

#### Transactions list
- **Filter bar**: type chips (Expense, Income, Transfer), date range, account, category. Persists across navigations.
- **List**: reverse-chronological. Each row shows: type icon, description (or category if blank), account, signed amount in account's currency. Soft-deleted transactions hidden by default; toggle to show them (greyed out).
- **Group headers**: by day, by month-section.
- **Row tap**: opens transaction details.
- **Row long-press / overflow menu**: Edit, Soft-delete, Duplicate.
- **Empty state**: "No transactions match the current filters" with a "Clear filters" button.

#### Transaction details / edit
- Shows all legs, the category, the description, the date, and the chain metadata (`lineId`, `prev`) in a collapsible "Debug" section.
- Edit reopens the appropriate flow with fields prefilled.
- Soft-delete confirmation modal.

#### Accounts list
- **Grouped by root segment** (Chase::, Citi::, Cash::, …).
- Each row: account path, account type icon, balance per currency (one line each).
- **The built-in Expense and Income accounts appear in their own pinned section** ("System accounts") and are read-only — no edit, no delete. Their "balance" is shown but framed as "Total expenses / Total income" since they're external buckets.
- "+" button on the list bar opens "New Account" dialog (name, type, initial currency optional). The type picker excludes `expense` and `income` for user-created accounts.

#### Account details
- Header: path, type, current balance per currency.
- Tabs: **Transactions** (just legs touching this account), **Balance history** (line chart over time).
- Edit / Soft-delete in overflow menu (disabled for the built-ins).

#### Categories list (reachable from Settings or via Add Transaction)
- Tree view with `::` hierarchy. Roots are expandable.
- Each row: icon, name, count of transactions using it (rough denormalised hint).
- Tap a root: edit its icon and color (inherited by children).
- "+" creates a new root or descendant.
- Soft-delete moves a category to a "deleted" section; transactions referencing it keep the path string intact.

#### Currencies list (Settings)
- Grouped by type: Fiat / Stock / Crypto.
- Each row: code, name, symbol, decimal places, "default" toggle (one default fiat).
- "+" adds a custom currency. Currency code is the unique key — users can add `AAPL` (stock), `BTC` (crypto), etc.

#### Reports
A single hub with cards/tiles for each report. Tapping a card opens the drilldown.

- **Spending by category** — pie or bar chart of expenses grouped by category at depth 1; tap a slice to drill in to depth 2, then to the underlying transactions. Powered by `ledger.query(filter, groupBy: [byCategory(depth: …)])`.
- **Income vs expense over time** — stacked bar chart per month/week, configurable. Powered by `ledger.query(filter, groupBy: [byTime(month), byTransactionType])` (`byTransactionType` is planned; until then a small `LedgerView` per tx-type with a time grouping does the same job).
- **Net worth trend** — line chart: asset-account balances summed (in default currency) over time. Time-bucketed.
- **Budget vs actual** — per-category budget set in Settings; progress bar per category for the current period.
- **Account balances** — grouped view of every asset/liability account's current balance with multi-currency support.

Every report shares a top filter bar (date range, account, category). Filter state persists between navigations.

#### Settings
- **Sync folder** — current path, "Change folder" (file picker), sync status indicator.
- **Currencies** — opens currencies list.
- **Categories** — opens categories list.
- **Budgets** — opens budget editing screen (Phase 3.5).
- **Default currency** — picker.
- **Period for dashboard** — month / week / pay-cycle.
- **Theme** — system / light / dark; (later) KDE / GTK on Linux.
- **Data tools** — "Force re-sync", "Rebuild pre-computed views", "Export JSONL".
- **About** — version, license, link to repo.

### Cross-cutting UI rules

- **Money formatting**: always via `intl` + the currency's `decimalPlaces`. Sign-aware: expenses red, income green. Cross-currency views show both sides of a transfer.
- **Account picker grouping**: by root segment of the `::` path. The built-in Expense and Income accounts are filtered *out* of pickers used for asset/liability selection (Expense and Transfer flows). They appear only in the System-accounts section of the Accounts list and as bare balancing legs in Transaction details.
- **Category picker UX**: icon grid for roots → search-driven fuzzy match → "Create new category" inline confirmation. Inline creation generates a new `Category` with `parentType` derived from the flow (expense vs income) and inherits the parent root's icon/color.
- **Soft delete is reversible**: every list with deletable items offers "Show deleted" and "Restore". The append-only JSONL keeps the history.
- **Validation surfaces inline**: `Transaction.validate()` returns a `ValidationResult` with a message; the form shows it under the offending field. Common cases: legs don't balance, cross-currency transfer missing exchange rate, category on a built-in account leg.
- **Sync status indicator** lives in the app bar: shows "synced", "syncing", "conflict — tap to resolve". The conflict screen lists `EntityConflict`s with side-by-side "yours" vs "theirs" diffs and a per-entity pick (Phase 1.9).
- **Pre-computed views are invisible to users**: balance / spending lookups feel instant. The "Rebuild pre-computed views" button in Settings exists for support; under normal use, push updates keep them fresh (Phase 1.8).

### Out of scope for v0 design
- Tags (separate from categories) — not yet modeled.
- Recurring transactions — not yet modeled.
- Multi-user / shared ledgers — single-user app.
- Receipt attachments — single-user app, no asset store.

## Engine ↔ UI contract

When wiring providers in Phase 2, expose `LedgerService` through a single Riverpod provider; derive read-side providers (`accountsProvider`, `categoriesProvider`, `transactionsProvider`, plus query-backed `balanceProvider`, `monthlySpendingProvider`, etc.) from it. Writes always go through `ledger.save` / `saveAll` / `delete` — never reach into a repository directly from the UI.

Pre-computed views (`LedgerView`, Phase 1.8 PRs B/C) are the right abstraction for any report or dashboard card that re-renders frequently. Each card maps to one named view; the provider listens for view updates and rebuilds on change.

## Per-phase workflow

After completing each phase:
1. `flutter test` and `flutter analyze` — both must be clean.
2. Commit with a focused message.
3. Open a PR; do not start the next phase until the user reviews/merges.
4. If review comments come back, address them as additional commits on the same PR.

The phase plan lives in `Plan.md` (gitignored). The high-level milestone structure: M1 = engine library, M2 = CRUD UI, M3 = reports. Phase 1.8 is split into PR A (Stat functor refactor), PR B (LedgerView in-memory), PR C (sembast persistence).

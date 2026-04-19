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
3. Send a PR

### Commands
- `flutter run -d linux` — run Linux desktop app
- `flutter build linux` — release build
- `flutter test` — unit + widget tests
- `flutter test integration_test/` — integration tests (needs running emulator or Linux desktop)
- `flutter analyze` — static analysis
- `dart run build_runner build` — regenerate freezed/json_serializable code

## Architecture

```
lib/
  main.dart
  app.dart                          # MaterialApp, theme, routing

  models/                           # freezed data classes
    account.dart
    category.dart
    currency.dart
    transaction.dart
    leg.dart

  data/                             # data layer
    storage/
      jsonl_store.dart              # generic JSONL read/write/append
      file_sync.dart                # conflict detection & merge
    repositories/
      account_repository.dart
      category_repository.dart
      transaction_repository.dart
      currency_repository.dart

  services/                         # business logic
    ledger_service.dart             # double-entry validation, balance computation
    report_service.dart             # aggregations, trends, filtering
    sync_service.dart               # folder watching, conflict resolution

  ui/
    screens/
      home/                         # dashboard with summary cards
      transactions/                 # list, add, edit transactions
      accounts/                     # account list, balances
      categories/                   # category & tag management
      reports/                      # charts, trends, filters
      settings/                     # sync folder config, currency setup
    widgets/                        # shared UI components
      transaction_form.dart
      account_picker.dart
      category_picker.dart
      currency_input.dart
      balance_card.dart

  providers/                        # Riverpod providers
    ...
```

### Key Dependencies
- `flutter_riverpod` — state management
- `freezed` + `json_serializable` — typed immutable models with JSON serialization
- `uuid` — entity IDs
- `decimal` — precise money arithmetic (no floating point)
- `fl_chart` — charts for reports
- `file_picker` — sync folder selection
- `path_provider` — app data directories
- `intl` — date/number formatting
- `fuzzy` or similar — fuzzy search for category path input

## Data Model

### Double-Entry Bookkeeping
Every transaction is a journal entry with 2+ legs (debit/credit). The UI is simplified (user picks category + account), but the data model is full double-entry.

**Account types**: Assets, Liabilities, Income, Expenses, Equity

**Invariant**: For same-currency transactions, sum of all legs = 0. For cross-currency transfers, the exchange is recorded in metadata.

### Entities

**Currency**: `id, code (USD/EUR/AAPL/BTC), name, type (fiat/stock/crypto/custom), symbol?, decimalPlaces`

**Account** (hierarchical, manually created): `id, path (Chase::Checking), type, isVirtual, notes?, createdAt`
- `::` separator, shallow depth (1-2 levels)
- Grouped in UI by shared prefix
- Balances computed per-currency from transactions

**Category** (hierarchical, dynamically created): `id, path (Food::Snacks::Cake), parentType (income/expense), icon?, color?`
- `::` separator, arbitrary depth
- Created on-the-fly during transaction entry
- Root categories shown as grid; deeper paths via fuzzy search
- Icon/color set on root categories, inherited by children

**Transaction** (Journal Entry): `id, date, description, type (expense/income/transfer), legs[], metadata?, createdAt, updatedAt?, deleted`

**Leg**: `accountId, amount (positive=debit, negative=credit), currencyCode, categoryPath?`

### Double-Entry Examples

Simple expense ($50 groceries):
```
Leg 1: Debit  Expenses:Food      +50.00 USD  (category: Food::Groceries)
Leg 2: Credit Assets:Checking    -50.00 USD
```

Stock purchase (10 AAPL at $200):
```
Leg 1: Credit Assets:Checking     -2000.00 USD
Leg 2: Debit  Assets:Fidelity       +10.00 AAPL
metadata: { exchangeRate: { from: "USD", to: "AAPL", rate: 0.005, inverse: 200.0 } }
```

## File Format

Append-only JSONL, split by type: `transactions.jsonl`, `accounts.jsonl`, `categories.jsonl`, `currencies.jsonl`

Edits/deletes append a new line with the same UUID and newer timestamp. State is reconstructed by keeping only the latest version per UUID. No compaction — if storage becomes an issue, migrate to a dedicated DB.

### Conflict Resolution
On startup, scan sync folder for conflict copies (e.g., `transactions (1).jsonl`), merge by UUID (latest `updatedAt` wins), write merged result, delete conflict copies.

## Testing Strategy

### Layer 1: Unit Tests
- Data models, repositories, services (ledger validation, balance computation)
- Pure Dart, no Flutter dependencies needed for most
- `flutter test test/`

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

### Transaction Types & UX

| Type | UI Flow | Legs Created |
|------|---------|-------------|
| Expense | Amount -> Category -> Account | Debit: Expense, Credit: Asset/Liability |
| Income | Amount -> Category -> Account | Credit: Income, Debit: Asset |
| Transfer | From -> To -> Amount(s) | Credit: Source, Debit: Destination |

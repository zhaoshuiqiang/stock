# AGENTS

## Project Overview

Flutter (Dart) A-share stock analysis Android app. Pure client-side rule engine — no backend server. All technical analysis computed locally from K-line data fetched via public stock APIs (EastMoney/Tencent/Sina). Optional AI enhancement via ChatCompletion API (Zhipu/OpenRouter/CliProxy).

- **Entry point**: `mobile/lib/main.dart`
- **Version**: `mobile/pubspec.yaml` + `mobile/lib/core/app_version.dart` (currently v4.2.20260718)
- **Python env**: `venv/` (akshare for concept data generation)
- **Stats**: ~141 Dart source files, 105 test files, 1061 tests
- **Toolchain (pinned in `.tool-versions`)**: Flutter 3.44.0 stable (bundles Dart 3.12.0), JDK 17, Android SDK API 36+ — run `flutter doctor` to verify.

## Developer Commands

```bash
# Setup — toolchain versions are pinned in .tool-versions
#   (Flutter 3.44.0 stable / Dart 3.12.0; JDK 17). Verify first, then fetch:
flutter doctor
cd mobile && flutter pub get

# Run all tests (1061 tests, 6 skipped — hot_sectors_test requires network)
cd mobile && flutter test

# Run single test
cd mobile && flutter test test/signal_engine_test.dart

# Build APK
powershell -File mobile/build_release.ps1
# Output: d:\MyProjects\stock\stock-vX.Y.Z.apk

# Manual build
cd mobile && flutter build apk --release

# Run on emulator
flutter emulators --launch StockEmulator
flutter run -d emulator-5554
```

### Environment Variables

```powershell
# <REPO_ROOT> = absolute path where this repo is checked out on your machine
#   (this machine: D:\MyProjects\stock). The Android SDK is bundled inside
#   the repo, so ANDROID_HOME and ANDROID_SDK_ROOT MUST point to the same dir.
ANDROID_HOME=<REPO_ROOT>\android-sdk
ANDROID_SDK_ROOT=<REPO_ROOT>\android-sdk
ANDROID_AVD_HOME=<REPO_ROOT>\android-emulator
```

> The definitive SDK path is `sdk.dir` in `mobile/android/local.properties`
> (git-ignored, per-machine). Keep the variables above consistent with it.

## Version Release (3 files must update together)

1. `mobile/pubspec.yaml` → `version: X.Y.Z`
2. `mobile/lib/core/app_version.dart` → `static const String version = 'X.Y.Z';`
3. `mobile/lib/screens/update_log_screen.dart` → Add new version entry to `updates` list
> Enforced by `mobile/test/release_ritual_guard_test.dart` (run `cd mobile && flutter test test/release_ritual_guard_test.dart`): fails when the three declared versions drift apart.

## Architecture

### Analysis Pipeline (`signal_engine.dart` → `generateAnalysis()`)

```
API (K-line + Quotes)
  │
  ├─ 1.  Signal Detection (signal_layer → signal_detector)
  │      Short/Medium/Long: KDJ/RSI/MA/MACD/BOLL/CCI/WR/Gaps/Candlesticks
  │      + Composite signals + Dynamic confidence + Signal decay
  │
  ├─ 1a. Market Structure (market_structure_analyzer) — 5 types
  ├─ 1b. Percentile Analysis (percentile_analyzer) — PE/PB/RSI/Volume percentiles
  │
  ├─ 2.  Technical Scorer (5-dim: signal/trend/momentum/volume/volatility)
  ├─ 3.  Realtime Scorer (倒U型: 温和上涨最优, 涨幅>3%惩罚追高)
  ├─ 4.  Confluence Scorer (10-indicator cross-confirmation)
  ├─ 4a. Capital Flow Analyzer (主力净流入/5日10日趋势/OBV/连续性/蓄积模式)
  │
  ├─ 5.  Comprehensive Scorer (7-dim weighted fusion)
  │      技术33% + 资金18% + 实时16% + 共振12% + 情绪10% + 基本面7% + 结构4%
  │      + Chase penalty: 涨幅>3%大幅惩罚
  │      + Short-term mode: 技术40% + 资金25% + 实时20% + 共振10% + 结构5%
  │
  ├─ 6.  Reason Generation (含追高风险警告)
  ├─ 7.  Risk Analyzer (5维)
  ├─ 8.  Opportunity Identifier (5维评分 + 信号协同矩阵)
  ├─ 9.  Suggestion Generator (ATR动态仓位 + 分层止损)
  │
  ├─ 9a. Short-term Decision Engine (v3 core)
  │      5-dim evidence → direction → execution gates → 9-level recommendation
  │      Direction: trend25% + reversal_momentum25% + volume_flow20% + relative_strength15% + sector_momentum10% + next_session5%
  │      Gates: trade_quality + risk + evidence_confidence
  │      Calibration: 1/3/5-day Wilson interval + Beta-Binomial posterior
  │
  ├─ 10. Mega Backtest (6 strategies, A-share cost model, walk-forward validation)
  ├─ 11. Strategy Builder (short 6-8 + long 6-8 + special 2-3, structure-aware)
  ├─ 12. Confidence Calculator (8-dim)
  └─ 13. Trade Levels (ATR dynamic stop-loss, trailing stop, tiered take-profit)
```

### Key Data Flow

- **`AnalysisResult`** — central output model, aggregates all sub-results
- **`ExploreResult`** — flattened summary for batch scan display (DiscoverScreen)
- **`ShortTermDecision`** — v3 short-term decision: direction/quality/risk/confidence/calibration
- **`DecisionSnapshotRecord`** → **`DecisionOutcomeRecord`** — decision tracking with 1/3/5-day outcomes
- **`RecommendationTracker`** — records snapshots when score ≥ 6, tracks 5/10/20-day returns
- **`ConceptTagProvider`** — singleton loads `concept_tags.json` at startup
- **`MarketStructureAnalyzer`** — uses ADX + MA alignment (no new data needed)

### Directory Map

| Directory | Files | Purpose |
|-----------|-------|---------|
| `mobile/lib/analysis/` | 80 | All analysis engines |
| `mobile/lib/models/` | 3 | `stock_models.dart` (central, 2631 lines), `short_term_decision.dart`, `short_term_direction.dart` |
| `mobile/lib/screens/` | 20 | UI pages |
| `mobile/lib/widgets/` | 16 | Reusable UI components |
| `mobile/lib/api/` | 4 | HTTP client + market context + timeshare parser + polling client |
| `mobile/lib/storage/` | 3 | SQLite (database_service.dart, v24) + portfolio asset store |
| `mobile/lib/data/` | 2 | Static data providers (concept_tag_provider, indicator_reference) |
| `mobile/lib/validators/` | 1 | Data validation pipeline (7 anomaly types) |
| `mobile/lib/core/` | 6 | App version, trading calendar, trading session, stock code utils, AI config, navigator key |
| `mobile/lib/services/` | 3 | Notification service, decision CSV exporter, legacy archive CSV exporter |
| `scripts/` | 10+ | Python utilities (build_concept_tags.py, analysis/fix scripts) |

### Key Analysis Subsystems

| Subsystem | Key Files | Purpose |
|-----------|-----------|---------|
| Signal Detection | `signal_engine`, `signal_detector`, `signal_layer`, `signal_evidence_classifier`, `signal_validator` | Layered + composite signals, adversarial validation |
| Scoring | `technical_scorer`, `realtime_scorer`, `confluence_scorer`, `comprehensive_scorer`, `short_term_scorer`, `recommendation_calibrator` | Multi-dim scoring + chase penalty |
| Short-term Decision | `short_term_decision_engine`, `directional_evidence_builder`, `recommendation_policy`, `short_term_direction_model`, `short_term_risk_evaluator`, `trade_quality_evaluator`, `evidence_confidence_calculator`, `primary_strategy_selector` | 5-dim evidence → 9-level recommendation |
| Decision Tracking | `decision_tracker`, `decision_outcome_evaluator`, `decision_statistics`, `decision_calibrator`, `decision_calibration_service`, `calibration_metrics` | Snapshot capture + 1/3/5-day hit rate + Wilson interval |
| Prediction | `next_day_predictor`, `next_session_predictor`, `next_session_feature_extractor`, `next_session_backtest` | KNN prediction + walk-forward validation |
| Market Analysis | `market_structure_analyzer`, `market_regime_classifier`, `percentile_analyzer`, `sector_rotation`, `sector_heat_detector`, `structure_transition_detector` | Structure/regime/sector analysis |
| Capital & Sentiment | `capital_flow_analyzer`, `fundamental_analyzer`, `news_sentiment_analyzer`, `sentiment_thermometer`, `debate_engine` | Fund flow + sentiment + AI debate |
| Limit-up | `limit_up_analyzer`, `limit_up_scan_engine`, `limit_up_universe_provider` | Limit-up batch analysis + pool |
| Intraday | `intraday_analyzer`, `intraday_level_analyzer`, `intraday_data_provider`, `intraday_scan_engine` | 5-min K-line patterns + signals |
| AI Layer | `ai_layer.dart` | 3 providers (Zhipu/OpenRouter/CliProxy), 7 methods, rate limiting, retry + NullAILayer fallback |

### API Module

| File | Purpose |
|------|---------|
| `api_client.dart` (~2197 lines) | EastMoney + Tencent + Sina, parallel racing (Completer-based), 5-min cache, in-flight dedup, HTTP retry |
| `market_context_provider.dart` | Sina → EastMoney fallback |
| `timeshare_parser.dart` | EastMoney intraday data parser |
| `websocket_client.dart` | HTTP polling client (5s interval, 3s for positions) |

### Database (SQLite v24)

**File**: `stock_analysis.db` — Migrations follow `if (oldVersion < N)` pattern in `database_service.dart`.

| Table | Purpose | Version |
|-------|---------|---------|
| `watchlist` | Watchlist | v1 |
| `alerts` | Alert records | v1+ |
| `archive_records` | Archive records | v3 |
| `explore_results` / `opportunity_results` / `sector_pick_results` | Scan results | v4–v6 |
| `home_cache` | Home page cache | v7 |
| `recommendation_tracking` | 5/10/20-day returns | v8 |
| `decision_snapshots` / `decision_outcomes` | Decision tracking (30+ fields) | v21 |
| `limit_up_pool` | Limit-up pool | v17 |
| `portfolio_snapshots` | Portfolio snapshots | v19 |

## Key Conventions

- **New analysis modules**: Static utility classes (e.g., `MarketStructureAnalyzer.analyze()`)
- **Model fields**: Always nullable for backward compatibility, defaults in constructors
- **Error handling**: Defensive `try/catch` with `debugPrint` logging for non-critical paths
- **Colors**: Defined as `const _k*` at top of screen files; red=up, green=down (A股 convention)
- **Version bumps**: Update `pubspec.yaml`, `app_version.dart`, and `update_log_screen.dart` together
- **Plan files**: Stored in `docs/superpowers/plans/` and `docs/superpowers/specs/`
- **File encoding**: Must use Python scripts to modify Dart files containing Chinese characters (Edit tool / PowerShell corrupts UTF-8) Enforced by `mobile/test/release_ritual_guard_test.dart` (scans `lib/**/*.dart` for U+FFFD / invalid UTF-8).
- **API parallel racing**: `_fetchStockHistory` uses Completer-based parallel racing, first success returns

## Modules WITHOUT Tests (priority for coverage)

- `ai_layer.dart` (824 lines) — core AI service
- `news_sentiment_analyzer.dart` (274 lines) — sentiment analysis
- `notification_service.dart` (698 lines) — push notifications
- `fundamental_analyzer.dart` — fundamental scoring
- `pattern_recognizer.dart` — K-line pattern recognition
- `market_timing.dart` — market timing
- `position_manager.dart` — position sizing

## Known Issues

1. **API Key handling (fixed v4.18)** — `assets/secrets.json` was removed from `pubspec.yaml` assets in v4.18, so release APKs no longer bundle it (verified by unpacking). Keys are now injected at runtime via Settings (persisted to SharedPreferences) or environment variables. Rotate any keys shipped in APKs v4.17 or earlier, since those builds distributed them in plaintext.
2. **ROE data source not integrated** — `comprehensive_scorer.dart` TODO: fundamental scoring lacks ROE (uses default 5.0).
3. **MA120 unavailable** — Alert system MA cross only supports up to MA60.
4. **AI layer + notification service lack tests** — 1522 lines with zero test coverage.
5. **`hot_sectors_test.dart`** — Requires live network, skipped in offline CI.

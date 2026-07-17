# AGENTS

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

Flutter (Dart) A-share stock analysis Android app. Pure client-side rule engine — no backend server. All technical analysis computed locally from K-line data fetched via public stock APIs (EastMoney/Tencent/Sina). Optional AI enhancement via ChatCompletion API (Zhipu/OpenRouter/CliProxy).

- **Entry point**: `mobile/lib/main.dart`
- **Version**: `mobile/pubspec.yaml` + `mobile/lib/core/app_version.dart` (currently v3.35.20260717)
- **Python env**: `venv/` (akshare for concept data generation)
- **Codebase size**: ~35,000+ lines Dart (lib/), 148 source files, 102 test files, 1008+ tests

## Development Workflow

### 1. Development Environment

| Component | Path |
|-----------|------|
| Flutter SDK | `D:\flutter` |
| Android SDK | `D:\MyProjects\stock\android-sdk` |
| Emulator (AVD) | `D:\MyProjects\stock\android-emulator` (non-C drive) |

#### Environment Variables

```powershell
ANDROID_HOME=D:\MyProjects\stock\android-sdk
ANDROID_SDK_ROOT=D:\Users\zsq53\Desktop\stock\android-sdk
ANDROID_AVD_HOME=D:\MyProjects\stock\android-emulator
```

### 2. Complete Workflow (Dev → Build → Test → Commit)

```
Step 1: Setup     → git clone && cd mobile && flutter pub get
Step 2: Develop   → Edit mobile/lib/ files, hot reload with R
Step 3: Test      → cd mobile && flutter test (1008+ tests)
Step 4: Build     → powershell -File mobile/build_release.ps1
Step 5: Commit    → git add ... && git commit -m "vX.Y.Z: Desc" && git push
```

### 3. Detailed Steps

#### 3.1 Dev Environment Setup

```bash
git clone https://github.com/zhaoshuiqiang/stock.git
cd stock/mobile && flutter pub get
flutter emulators --launch StockEmulator
flutter run -d emulator-5554
```

#### 3.2 Running Tests

```bash
# Run all tests (1008+ tests, 102 files)
cd mobile && flutter test

# Run single test file
cd mobile && flutter test test/signal_engine_test.dart

# Note: hot_sectors_test.dart requires network access, will fail offline
```

**Test Coverage**

| Category | Test Files | Key Files |
|----------|-----------|-----------|
| Signal Detection | 3+ | signal_engine_test, signal_detector_confluence_test, signal_layer_test |
| Scoring | 5 | scoring_logic_test, technical_scorer_test, realtime_scorer_test, confluence_scorer_test, short_term_scorer_test |
| Short-term Decision | 3+ | short_term_decision_engine_test, directional_evidence_builder_test, recommendation_policy_test |
| Decision Tracking | 6 | decision_tracker_test, decision_outcome_evaluator_test, decision_statistics_test, decision_tracking_db_test |
| Calibration | 4 | calibration_metrics_test, decision_calibrator_test, decision_calibration_service_test |
| Backtest | 3 | backtest_validation_test, backtest_benchmark_test, strategy_engine_test |
| Next-session Prediction | 5 | next_session_predictor_test, next_session_backtest_test, next_session_feature_extractor_test |
| Limit-up Analysis | 7 | limit_up_scan_engine_test, limit_up_analyzer_batch_test, limit_up_pool_db_test |
| Market Analysis | 4 | market_structure_analyzer_test, market_regime_classifier_test, sentiment_thermometer_test |
| API Parsing | 4 | api_parsing_test, kline_api_test, sector_ranking_api_test, timeshare_parser_test |
| Data Validation | 2 | data_validation_test, data_validation_pipeline_test |
| Models | 3 | stock_models_test, short_term_decision_model_test, short_term_direction_model_test |
| UI/Widget | 3+ | archive_screen_decision_test, trading_dashboard_decision_test |
| Integration/Regression | 3 | p0_integration_test, refactor_regression_test, code_review_fixes_test |

**Modules WITHOUT tests** (priority for future coverage):
- `ai_layer.dart` (824 lines) — core AI service
- `news_sentiment_analyzer.dart` (274 lines) — sentiment analysis
- `notification_service.dart` (698 lines) — push notifications
- `fundamental_analyzer.dart` — fundamental scoring
- `pattern_recognizer.dart` — K-line pattern recognition
- `market_timing.dart` — market timing
- `position_manager.dart` — position sizing

#### 3.3 Building APK

```bash
# Recommended: PowerShell script
powershell -File mobile/build_release.ps1
# Output: d:\MyProjects\stock\stock-vX.Y.Z.apk (~61MB)

# Manual
cd mobile && flutter build apk --release
```

#### 3.4 Version Release (3 files must update together)

1. `mobile/pubspec.yaml` → `version: X.Y.Z`
2. `mobile/lib/core/app_version.dart` → `static const String version = 'X.Y.Z';`
3. `mobile/lib/screens/update_log_screen.dart` → Add new version entry to `updates` list

#### 3.5 Code Review Checklist

- [ ] No dead code (unused variables/methods)
- [ ] Proper error handling (try/catch)
- [ ] Null safety compliance
- [ ] Consistent naming conventions
- [ ] Performance: no unnecessary computation
- [ ] UI: consistent colors (red=up, green=down, A-share convention) and spacing
- [ ] Version bump: pubspec.yaml + app_version.dart + update_log_screen.dart

## Architecture

### Analysis Pipeline (`signal_engine.dart` → `generateAnalysis()`)

```
API (K-line + Quotes)
  │
  ├─ 1.  Signal Detection (signal_layer → signal_detector)
  │      Short/Medium/Long: KDJ/RSI/MA/MACD/BOLL/CCI/WR/Gaps/Candlesticks
  │      + Composite signals: 缩量蓄势突破/底部连阳/跳空回补
  │      + Dynamic confidence: KDJ by K-value, RSI by RSI-value, WR by extremity
  │      + Signal decay: effectiveConfidence by indicator type
  │
  ├─ 1a. Market Structure (market_structure_analyzer)
  │      5 types: bullTrend/bearTrend/consolidation/accumulation/distribution
  │
  ├─ 1b. Percentile Analysis (percentile_analyzer)
  │      PE/PB industry percentiles + RSI + Volume ranking
  │
  ├─ 2.  Technical Scorer (5-dim: signal/trend/momentum/volume/volatility)
  ├─ 3.  Realtime Scorer (倒U型: 温和上涨最优, 涨幅>3%惩罚追高)
  ├─ 4.  Confluence Scorer (10-indicator cross-confirmation)
  ├─ 4a. Capital Flow Analyzer (主力净流入/5日10日趋势/OBV/连续性/蓄积模式)
  │
  ├─ 5.  Comprehensive Scorer (7-dim weighted fusion)
  │      技术33% + 资金18% + 实时16% + 共振12% + 情绪10% + 基本面7% + 结构4%
  │      + Chase penalty: 涨幅>3%大幅惩罚, >3%时惩罚不受动量保护削弱
  │      + Short-term mode: 技术40% + 资金25% + 实时20% + 共振10% + 结构5%
  │
  ├─ 6.  Reason Generation (含追高风险警告: 涨幅>3%)
  ├─ 7.  Risk Analyzer (技术/量价/趋势/振幅/涨跌幅 5维)
  ├─ 8.  Opportunity Identifier (5维评分 + 信号协同矩阵)
  ├─ 9.  Suggestion Generator (ATR动态仓位 + 分层止损)
  │
  ├─ 9a. Short-term Decision Engine (v3 core)
  │      5-dim evidence → direction → execution gates → 9-level recommendation
  │      Direction: trend30% + reversal_momentum25% + volume_flow20% + relative_strength15% + next_session10%
  │      Gates: trade_quality + risk + evidence_confidence
  │      Calibration: 1/3/5-day Wilson interval + Beta-Binomial posterior
  │
  ├─ 10. Mega Backtest (6 strategies, A-share cost model, walk-forward validation)
  ├─ 11. Strategy Builder (short 6-8 + long 6-8 + special 2-3, structure-aware)
  ├─ 12. Confidence Calculator (8-dim: consistency+trend+volume+fundamental+sentiment+backtest+adversarial+prediction)
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
| `mobile/lib/analysis/` | 80 | All analysis engines (signal detection, scoring, decision, backtest, prediction, market, capital, sentiment, limit-up, intraday) |
| `mobile/lib/models/` | 3 | Data models — `stock_models.dart` (2631 lines, central), `short_term_decision.dart`, `short_term_direction.dart` |
| `mobile/lib/screens/` | 24 | UI pages (home, discover, watchlist, quote, archive, sector, quant, etc.) |
| `mobile/lib/widgets/` | 21 | Reusable UI components (trading_dashboard, signal_card, strategy_panel, etc.) |
| `mobile/lib/api/` | 4 | HTTP client + market context + timeshare parser + polling client |
| `mobile/lib/storage/` | 3 | SQLite (database_service.dart, v24) + portfolio asset store |
| `mobile/lib/data/` | 2 | Static data providers (concept_tag_provider, indicator_reference) |
| `mobile/lib/validators/` | 1 | Data validation pipeline (7 anomaly types) |
| `mobile/lib/core/` | 6 | App version, trading calendar, trading session, stock code utils, AI config, navigator key |
| `mobile/lib/services/` | 3 | Notification service, decision CSV exporter, legacy archive CSV exporter |
| `scripts/` | 10+ | Python utilities (build_concept_tags.py, analysis/fix scripts) |

### Analysis Module Inventory (80 files in `mobile/lib/analysis/`)

#### Signal Detection (5 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `signal_engine.dart` | `generateAnalysis()` | **Main entry**: 13-step pipeline orchestration |
| `signal_detector.dart` | `SignalDetector.detectLayeredSignals()` | Layered signal detection: short/medium/long |
| `signal_layer.dart` | `SignalLayer.detectAllSignals()` | Merge layered + composite signals |
| `signal_evidence_classifier.dart` | `SignalEvidenceClassifier.classify()` | Map signals to 5-dim decision components |
| `signal_validator.dart` | `SignalValidator.validate()` | Adversarial validation: bear opposition / bull support |

#### Scoring (6 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `technical_scorer.dart` | `TechnicalScorer.score()` | Technical 5-dim: signal/trend/momentum/volume/volatility |
| `realtime_scorer.dart` | `RealtimeScorer.score()` | Inverted-U: 温和上涨最优, 追高惩罚, 跳空低开检测 |
| `confluence_scorer.dart` | `ConfluenceScorer.score()` | 10-indicator cross-confirmation |
| `comprehensive_scorer.dart` | `ComprehensiveScorer.combine()` | 7-dim weighted fusion + chase penalty |
| `short_term_scorer.dart` | `ShortTermScorer.score()` | Short-term operability: freshness + quality + chase risk |
| `recommendation_calibrator.dart` | `RecommendationCalibrator.calibrateScore()` | Downgrade on weak/conflicting evidence |

#### Short-term Decision Engine (8 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `short_term_decision_engine.dart` | `ShortTermDecisionEngine.evaluate()` | 5-dim evidence → direction → gates → 9-level recommendation |
| `directional_evidence_builder.dart` | `DirectionalEvidenceBuilder.build()` | 5-dim direction evidence: trend30% + reversal25% + volume20% + strength15% + next10% |
| `recommendation_policy.dart` | `RecommendationPolicy.evaluate()` | 9-level: direction → strength → gates → recommendation |
| `short_term_direction_model.dart` | `ShortTermDirectionModel.evaluate()` | Direction probability: de-momentum bias + market regime gating |
| `short_term_risk_evaluator.dart` | `ShortTermRiskEvaluator.evaluate()` | 5-dim risk: volatility + execution + chase + liquidity + event |
| `trade_quality_evaluator.dart` | `TradeQualityEvaluator.evaluate()` | 5-dim quality: timing + volume-price + liquidity + R:R + strategy |
| `evidence_confidence_calculator.dart` | `EvidenceConfidenceCalculator.calculate()` | 4-dim: consistency40% + coverage25% + freshness20% + stability15% |
| `primary_strategy_selector.dart` | `PrimaryStrategySelector.select()` | Select primary + supporting strategy |

#### Decision Tracking & Calibration (10 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `decision_tracker.dart` | `DecisionTracker.capture()` | Snapshot capture + 1/3/5-day hit rate tracking |
| `decision_outcome_evaluator.dart` | `DecisionOutcomeEvaluator.evaluate()` | Forward-adjusted price alignment + direction hit + Alpha |
| `decision_statistics.dart` | `DecisionStatisticsFilter` | Grouped stats: direction/market regime/model version/source |
| `decision_calibrator.dart` | `DecisionCalibrator.buildModel()` | Beta-Binomial posterior + Wilson confidence interval |
| `decision_calibration_service.dart` | `DecisionCalibrationService.enrich()` | Inject 1/3/5-day calibration probabilities |
| `calibration_metrics.dart` | `betaBinomialPosterior()`, `wilsonInterval()` | Wilson interval, Brier Score |
| `decision_score_diagnostics.dart` | `DecisionCorrelationResult` | Score diagnostics: direction distribution, score-outcome correlation |
| `decision_archive_filter.dart` | `DecisionArchiveViewFilter` | Archive view filtering |
| `decision_market_data_provider.dart` | `DecisionMarketDataProvider.load()` | Market data loading for evaluation (forward-adjusted K-line + benchmark) |
| `trading_date_utils.dart` | `TradingDateUtils.normalizeToTradeDate()` | Trading date normalization, signal phase detection |

#### Prediction (5 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `next_day_predictor.dart` | `NextDayPredictor.predict()` | Next-day probability: 7-dim weighted (ADX/MACD/KDJ/RSI/Volume/MA) |
| `next_session_predictor.dart` | `NextSessionPredictor.predict()` | K-nearest-neighbor prediction: feature extraction → similarity → weighted stats |
| `next_session_feature_extractor.dart` | `NextSessionFeatureExtractor.extract()` | 20-dim features: change/amplitude/close position/shadow/MA distance/volume ratio |
| `next_session_backtest.dart` | `NextSessionBacktest.run()` | Walk-forward validation + direction accuracy + Brier Score |
| `next_session_poc_report.dart` | `NextSessionPocReport.evaluate()` | POC report: high-confidence bucket win rate + cost deduction |

#### Backtest & Strategy (3 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `backtest_engine.dart` | `BacktestEngine.runMegaBacktest()` | 6-strategy mega backtest: A-share cost model + limit-up/down + forward-adjusted |
| `strategy_builder.dart` | `StrategyBuilder.buildLayeredStrategies()` | Layered strategy library: short 6-8 + long 6-8 + special 2-3 |
| `strategy_engine.dart` | `TradingStrategy` | Strategy model: ATR stop-loss/take-profit, holding days, max drawdown |

#### Market Analysis (7 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `market_structure_analyzer.dart` | `MarketStructureAnalyzer.analyze()` | 5 types: bull/bear/consolidation/accumulation/distribution |
| `market_regime_classifier.dart` | `MarketRegimeClassifier.classify()` | 7 regimes: bullTrend/bearTrend/rebound/pullback/range/highVolatility/unknown |
| `market_timing.dart` | `MarketTiming.fetchTiming()` | Market timing: sentiment + trend + position + tradeability |
| `percentile_analyzer.dart` | `PercentileAnalyzer.analyze()` | PE/PB percentile + RSI percentile + volume percentile |
| `sector_rotation.dart` | `SectorAnalysis` | Sector strength + mainline detection + rotation signals |
| `sector_heat_detector.dart` | `SectorHeatDetector.isOverheated()` | Overheat detection: 3 consecutive strong days + 5 limit-ups |
| `structure_transition_detector.dart` | `StructureTransitionDetector.detect()` | Structure transition: ADX + volume-price + MA confirmation |

#### Capital & Sentiment (5 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `capital_flow_analyzer.dart` | `CapitalFlowAnalyzer.analyze()` | Main net flow / 5d10d trend / OBV / continuity + accumulation patterns |
| `fundamental_analyzer.dart` | `FundamentalAnalyzer.analyze()` | Valuation (PE/PB) + profitability (ROE) + capital + liquidity + market cap |
| `news_sentiment_analyzer.dart` | `NewsSentimentAnalyzer.analyze()` | Keyword rules (30+ positive/negative) + negation + AI fallback |
| `sentiment_thermometer.dart` | `SentimentThermometer.compute()` | 6-dim (炸板率/连板率/封板率/赚钱效应/连板高度/恐慌) → temperature + phase |
| `debate_engine.dart` | `DebateEngine.debate()` | Bull/bear debate via AI layer |

#### Limit-up Analysis (3 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `limit_up_analyzer.dart` | `LimitUpStock`, `LimitUpAnalysis` | Limit-up data model + batch analysis (seal ratio / consecutive / first seal time) |
| `limit_up_scan_engine.dart` | `LimitUpScanEngine.scan()` | Scan coordinator: API → analysis → thermometer → persist |
| `limit_up_universe_provider.dart` | `LimitUpUniverseProvider.mergeAndDedup()` | DB cache + API merge + quote supplement + dedup |

#### Intraday Analysis (4 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `intraday_analyzer.dart` | `IntradayAnalyzer.analyze()` | Intraday patterns (7 types) + volume distribution + momentum + speed |
| `intraday_level_analyzer.dart` | `IntradayLevelAnalyzer.analyze()` | 8 signals: VWAP support/昨收支撑/底背离/急跌底部 + 4 sell signals |
| `intraday_data_provider.dart` | `IntradayDataProvider.fetchIntradayKline()` | 5-min K-line (48 bars), 5-min cache |
| `intraday_scan_engine.dart` | `IntradayScanEngine.scan()` | Batch scan: explore_results → intraday analysis → filter high-confidence |

#### Other Analysis (14 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `risk_analyzer.dart` | `RiskAnalyzer.analyze()` | 5-dim risk: technical + volume-price + trend + amplitude + change |
| `opportunity_identifier.dart` | `OpportunityIdentifier.identify()` | 5-dim scoring + signal synergy matrix |
| `suggestion_generator.dart` | `SuggestionGenerator.generate()` | Layered position (ATR dynamic) + stop-loss + strategy advice |
| `confidence_calculator.dart` | `ConfidenceCalculator.calculate()` | 8-dim: consistency+trend+volume+fundamental+sentiment+backtest+adversarial+prediction |
| `recommendation_tracker.dart` | `trackRecommendations()` | 5/10/20-day return tracking + reflection + Alpha + user feedback |
| `recommendation_explainer.dart` | `RecommendationExplainer.explain()` | Natural language recommendation rationale |
| `pattern_recognizer.dart` | `PatternRecognizer.detectAll()` | Classic patterns: double bottom / head-shoulders / triangle breakout |
| `momentum_persistence_analyzer.dart` | `MomentumPersistenceAnalyzer.analyze()` | ADX trend 40% + volume confirmation 30% + price deviation 30% |
| `position_manager.dart` | `PositionManager.calculatePosition()` | ATR dynamic position: higher volatility → lower position |
| `sr_quality.dart` | `SRQualityEvaluator.evaluateSupport()` | Support/resistance quality: test count + volume + timeliness + reliability |
| `weight_calibrator.dart` | `WeightCalibrator.calibrate()` | Strategy-level win rate based dynamic weight adjustment |
| `weight_calibration_cache.dart` | `WeightCalibrationCache.update()` | 4-hour expiry + old/new blend (0.7/0.3) |
| `weight_optimizer.dart` | `WeightOptimizer.getOptimizedWeights()` | 7-dim weight optimizer: auto-adjust based on historical hit rate |
| `indicators.dart` | `calcAllIndicators()` | **Technical indicator library**: MA/MACD/KDJ/RSI/BOLL/ATR/ADX/CCI/WR/OBV/BIAS/EMA |

#### Engine & Service (5 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `explore_engine.dart` | `ExploreEngine.explore()` | Batch scan: Shanghai/Shenzhen main board, filter buy-level stocks |
| `opportunity_engine.dart` | `OpportunityEngine` | Watchlist batch analysis |
| `sector_pick_engine.dart` | `SectorPickEngine.pick()` | Hot sector stock picking + mainline rotation bonus |
| `single_stock_analyzer.dart` | `SingleStockAnalyzer.analyze()` | Single stock complete analysis pipeline |
| `archive_service.dart` | `ArchiveService.archiveStock()` | Unified archive: dual-write archive_records + decision_snapshots |

#### AI Layer (2 files)
| File | Key Class/Method | Purpose |
|------|-----------------|---------|
| `ai_layer.dart` | `ChatCompletionLayer` | AI enhancement: 3 providers (Zhipu/OpenRouter/CliProxy), 7 methods, rate limiting, retry |
| `ai_layer.dart` | `NullAILayer` | Safe degradation when API key not configured |

### Screen Inventory (24 files in `mobile/lib/screens/`)

| Screen | Lines | Purpose | Status |
|--------|-------|---------|--------|
| `home_screen.dart` | ~727 | Short-term workstation: indices + hot sectors + limit-up + intraday + thermometer + sector picks | Active |
| `discover_screen.dart` | ~1789 | 5 tabs: 沪深扫描/打板梯队/分时低吸/板块精选/龙回头 | Active |
| `watchlist_screen.dart` | ~4266 | Watchlist + quotes + opportunity analysis + positions + Excel import + AI debate + archive + alerts | Active |
| `quote_screen.dart` | ~4199 | Stock detail: K-line + intraday + signals + tech panel + strategy + dashboard + AI + archive | Active |
| `archive_screen.dart` | — | Archive records + direction hit rate + decision snapshots + CSV export | Active |
| `sector_screen.dart` | — | Sector constituents + sector analysis | Active |
| `sector_overview_screen.dart` | — | Industry/concept sector ranking + distribution | Active |
| `quant_screen.dart` | — | Multi-condition screening + score ranking | Active |
| `global_market_screen.dart` | — | Global indices + commodities + FX | Active |
| `news_screen.dart` | — | Financial news + stock news + sentiment | Active |
| `alerts_screen.dart` | — | Price/indicator alert management | Active |
| `search_screen.dart` | — | Stock search + history | Active |
| `settings_screen.dart` | — | AI config + notification settings + data management | Active |
| `update_log_screen.dart` | — | Version update log | Active |
| `indicator_reference_screen.dart` | — | Technical indicator reference + scoring system | Active |
| `strategy_reference_screen.dart` | — | Trading strategy reference | Active |
| `scoring_explanation_screen.dart` | — | 7-dim scoring system explanation | Active |
| `recommendation_stats_screen.dart` | — | Recommendation hit rate + calibration | Active |
| `portfolio_chart_screen.dart` | — | Portfolio return curve + asset allocation | Active |
| `webview_screen.dart` | — | Embedded web browser | Active |
| ~~`chart_screen.dart`~~ | — | ~~K-line chart~~ | **Deleted** in v3.35 |
| ~~`signals_screen.dart`~~ | — | ~~Signal search~~ | **Deleted** in v3.35 |
| ~~`trend_signal_screen.dart`~~ | — | ~~Trend signal~~ | **Deleted** in v3.35 |
| ~~`dragon_retreat_screen.dart`~~ | — | ~~Dragon retreat~~ | **Deleted** in v3.35 |

### Widget Inventory (21 files in `mobile/lib/widgets/`)

| Widget | Purpose | Status |
|--------|---------|--------|
| `trading_dashboard.dart` | Comprehensive score + 7-dim radar + recommendation + position + stop-loss | Active |
| `analysis_result_card.dart` | Score + signals + strategy + next-day + next-session prediction | Active |
| `signal_card.dart` | Buy/sell signal list | Active |
| `strategy_panel.dart` | Strategy entry/exit/stop-loss rules | Active |
| `short_term_decision_panel.dart` | Direction + quality + risk + confidence + calibration | Active |
| `score_radar_chart.dart` | Score radar chart (fl_chart) | Active |
| `score_trend_chart.dart` | Score trend chart | Active |
| `stock_card.dart` | Stock card (discover/watchlist) | Active |
| `limit_up_card.dart` | Limit-up card (seal ratio / consecutive / first seal) | Active |
| `sentiment_thermometer_card.dart` | 6-dim indicators + temperature + phase | Active |
| `alert_dialog.dart` | Alert dialog | Active |
| `technical_indicators_panel.dart` | Technical indicator panel | Active |
| `decision_archive_summary.dart` | Decision archive summary | Active |
| `decision_snapshot_provenance_card.dart` | Decision snapshot provenance card | Active |
| `decision_score_diagnostics_panel.dart` | Decision score diagnostics panel | Active |
| `decision_calibration_summary.dart` | Decision calibration summary | Active |
| ~~`market_sentiment.dart`~~ | ~~Market sentiment bar~~ | **Deleted** in v3.35 |
| ~~`quote_card.dart`~~ | ~~Quote card~~ | **Deleted** in v3.35 |
| ~~`capsule_tab_switcher.dart`~~ | ~~Capsule tab switcher~~ | **Deleted** in v3.35 |
| ~~`strategy_panel_long.dart`~~ | ~~Long-term strategy panel~~ | **Deleted** in v3.35 |
| ~~`strategy_panel_short.dart`~~ | ~~Short-term strategy panel~~ | **Deleted** in v3.35 |

### API Module (4 files in `mobile/lib/api/`)

| File | Key Methods | Purpose |
|------|------------|---------|
| `api_client.dart` (~2197 lines) | `searchStocks`, `getRealtimeQuote`, `getBatchQuotes`, `getStockHistory`, `getForwardAdjustedHistory`, `getIntradayKline`, `getHotSectors`, `getSectorStocks`, `getMarketSentiment`, `getGlobalIndices`, `getTopicZTPool`, `getSectorRanking` | Core API client: EastMoney + Tencent + Sina, parallel racing (v3.34), 5-min cache, in-flight dedup, HTTP retry |
| `market_context_provider.dart` | `getMarketContext()` | Market context: Sina → EastMoney fallback |
| `timeshare_parser.dart` | `parseEastMoneyTrendLine()` | EastMoney intraday data parser |
| `websocket_client.dart` | `QuotePollingClient` | HTTP polling client (5s interval, 3s for positions) |

### Database (SQLite v24)

**Database file**: `stock_analysis.db`

| Table | Purpose | Version |
|-------|---------|---------|
| `watchlist` | Watchlist (code, name, is_pinned, added_at) | v1 |
| `alerts` | Alert records | v1+ |
| `archive_records` | Archive records (code, name, price, score, recommendation, risk_level) | v3 |
| `explore_results` | Explore scan results | v4 |
| `opportunity_results` | Opportunity analysis results | v5 |
| `sector_pick_results` | Sector pick results | v6 |
| `home_cache` | Home page cache | v7 |
| `recommendation_tracking` | Recommendation tracking (5/10/20-day returns) | v8 |
| `decision_snapshots` | Decision snapshots (30+ fields: direction/scores/regime/components) | v21 |
| `decision_outcomes` | Decision outcomes (snapshot_id, horizon, status, returns, hits) | v21 |
| `limit_up_pool` | Limit-up pool (code, name, consecutive_days, seal_amount, trade_date) | v17 |
| `portfolio_snapshots` | Portfolio snapshots (date, total_assets, total_cost, position_json) | v19 |

Migrations follow `if (oldVersion < N)` pattern in `database_service.dart`.

### Key Conventions

- **New analysis modules**: Static utility classes (e.g., `MarketStructureAnalyzer.analyze()`)
- **Model fields**: Always nullable for backward compatibility, defaults in constructors
- **Error handling**: Defensive `try/catch` with `debugPrint` logging for non-critical paths
- **Colors**: Defined as `const _k*` at top of screen files; red=up, green=down (A股 convention)
- **Version bumps**: Update `pubspec.yaml`, `app_version.dart`, and `update_log_screen.dart` together
- **Plan files**: Stored in `docs/superpowers/plans/` and `docs/superpowers/specs/`
- **File encoding**: Must use Python scripts to modify Dart files containing Chinese characters (Edit tool / PowerShell corrupts UTF-8)
- **API parallel racing**: `_fetchStockHistory` uses Completer-based parallel racing, first success returns (v3.34)

### Known Issues & Gaps

#### High Priority
1. **API Key in plaintext** — `assets/secrets.json` contains 3 API keys. Already in `.gitignore` (not committed), but should rotate keys periodically.

#### Medium Priority
2. **ROE data source not integrated** — `comprehensive_scorer.dart` TODO: fundamental scoring lacks ROE indicator (uses default 5.0).
3. **MA120 unavailable** — Alert system MA cross only supports up to MA60.
4. **AI layer + notification service lack tests** — 1522 lines of core service code with zero test coverage.

#### Low Priority
5. **Services directory thin** — Only 3 service files, no settings/crash-report infrastructure.
6. **`hot_sectors_test.dart`** — Requires live network, skipped in offline CI (v3.35).

<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

How to use skills:
- Invoke: `npx openskills read <skill-name>` (run in your shell)
  - For multiple: `npx openskills read skill-one,skill-two`
- The skill content will load with detailed instructions on how to complete the task
- Base directory provided in output for resolving bundled resources (references/, scripts/, assets/)

Usage notes:
- Only use skills listed in <available_skills> below
- Do not invoke a skill that is already loaded in your context
- Each skill invocation is stateless
</usage>

<available_skills>

<skill>
<name>algorithmic-art</name>
<description>Creating algorithmic art using p5.js with seeded randomness and interactive parameter exploration. Use this when users request creating art using code, generative art, algorithmic art, flow fields, or particle systems. Create original algorithmic art rather than copying existing artists' work to avoid copyright violations.</description>
<location>project</location>
</skill>

<skill>
<name>brand-guidelines</name>
<description>Applies Anthropic's official brand colors and typography to any sort of artifact that may benefit from having Anthropic's look-and-feel. Use it when brand colors or style guidelines, visual formatting, or company design standards apply.</description>
<location>project</location>
</skill>

<skill>
<name>canvas-design</name>
<description>Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art, design, or other static piece. Create original visual designs, never copying existing artists' work to avoid copyright violations.</description>
<location>project</location>
</skill>

<skill>
<name>claude-api</name>
<description>|-</description>
<location>project</location>
</skill>

<skill>
<name>doc-coauthoring</name>
<description>Guide users through a structured workflow for co-authoring documentation. Use when user wants to write documentation, proposals, technical specs, decision docs, or similar structured content. This workflow helps users efficiently transfer context, refine content through iteration, and verify the doc works for readers. Trigger when user mentions writing docs, creating proposals, drafting specs, or similar documentation tasks.</description>
<location>project</location>
</skill>

<skill>
<name>docx</name>
<description>"Use this skill whenever the user wants to create, read, edit, or manipulate Word documents (.docx files). Triggers include: any mention of 'Word doc', 'word document', '.docx', or requests to produce professional documents with formatting like tables of contents, headings, page numbers, or letterheads. Also use when extracting or reorganizing content from .docx files, inserting or replacing images in documents, performing find-and-replace in Word files, working with tracked changes or comments, or converting content into a polished Word document. If the user asks for a 'report', 'memo', 'letter', 'template', or similar deliverable as a Word or .docx file, use this skill. Do NOT use for PDFs, spreadsheets, Google Docs, or general coding tasks unrelated to document generation."</description>
<location>project</location>
</skill>

<skill>
<name>frontend-design</name>
<description>Guidance for distinctive, intentional visual design when building new UI or reshaping an existing one. Helps with aesthetic direction, typography, and making choices that don't read as templated defaults.</description>
<location>project</location>
</skill>

<skill>
<name>internal-comms</name>
<description>A set of resources to help me write all kinds of internal communications, using the formats that my company likes to use. Claude should use this skill whenever asked to write some sort of internal communications (status reports, leadership updates, 3P updates, company newsletters, FAQs, incident reports, project updates, etc.).</description>
<location>project</location>
</skill>

<skill>
<name>mcp-builder</name>
<description>Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services through well-designed tools. Use when building MCP servers to integrate external APIs or services, whether in Python (FastMCP) or Node/TypeScript (MCP SDK).</description>
<location>project</location>
</skill>

<skill>
<name>pdf</name>
<description>Use this skill whenever the user wants to do anything with PDF files. This includes reading or extracting text/tables from PDFs, combining or merging multiple PDFs into one, splitting PDFs apart, rotating pages, adding watermarks, creating new PDFs, filling PDF forms, encrypting/decrypting PDFs, extracting images, and OCR on scanned PDFs to make them searchable. If the user mentions a .pdf file or asks to produce one, use this skill.</description>
<location>project</location>
</skill>

<skill>
<name>pptx</name>
<description>"Use this skill any time a .pptx file is involved in any way — as input, output, or both. This includes: creating slide decks, pitch decks, or presentations; reading, parsing, or extracting text from any .pptx file (even if the extracted content will be used elsewhere, like in an email or summary); editing, modifying, or updating existing presentations; combining or splitting slide files; working with templates, layouts, speaker notes, or comments. Trigger whenever the user mentions \"deck,\" \"slides,\" \"presentation,\" or references a .pptx filename, regardless of what they plan to do with the content afterward. If a .pptx file needs to be opened, created, or touched, use this skill."</description>
<location>project</location>
</skill>

<skill>
<name>skill-creator</name>
<description>Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy.</description>
<location>project</location>
</skill>

<skill>
<name>slack-gif-creator</name>
<description>Knowledge and utilities for creating animated GIFs optimized for Slack. Provides constraints, validation tools, and animation concepts. Use when users request animated GIFs for Slack like "make me a GIF of X doing Y for Slack."</description>
<location>project</location>
</skill>

<skill>
<name>template</name>
<description>Replace with description of the skill and when Claude should use it.</description>
<location>project</location>
</skill>

<skill>
<name>theme-factory</name>
<description>Toolkit for styling artifacts with a theme. These artifacts can be slides, docs, reportings, HTML landing pages, etc. There are 10 pre-set themes with colors/fonts that you can apply to any artifact that has been creating, or can generate a new theme on-the-fly.</description>
<location>project</location>
</skill>

<skill>
<name>web-artifacts-builder</name>
<description>Suite of tools for creating elaborate, multi-component claude.ai HTML artifacts using modern frontend web technologies (React, Tailwind CSS, shadcn/ui). Use for complex artifacts requiring state management, routing, or shadcn/ui components - not for simple single-file HTML/JSX artifacts.</description>
<location>project</location>
</skill>

<skill>
<name>webapp-testing</name>
<description>Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.</description>
<location>project</location>
</skill>

<skill>
<name>xlsx</name>
<description>"Use this skill any time a spreadsheet file is the primary input or output. This means any task where the user wants to: open, read, edit, or fix an existing .xlsx, .xlsm, .csv, or .tsv file (e.g., adding columns, computing formulas, formatting, charting, cleaning messy data); create a new spreadsheet from scratch or from other data sources; or convert between tabular file formats. Trigger especially when the user references a spreadsheet file by name or path — even casually (like \"the xlsx in my downloads\") — and wants something done to it or produced from it. Also trigger for cleaning or restructuring messy tabular data files (malformed rows, misplaced headers, junk data) into proper spreadsheets. The deliverable must be a spreadsheet file. Do NOT trigger when the primary deliverable is a Word document, HTML report, standalone Python script, database pipeline, or Google Sheets API integration, even if tabular data is involved."</description>
<location>project</location>
</skill>

</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>

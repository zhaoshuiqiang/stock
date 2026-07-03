# AGENTS

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

Flutter (Dart) A-share stock analysis Android app. Pure client-side rule engine — no backend server, no LLM/API calls. All technical analysis computed locally from K-line data fetched via public stock APIs (EastMoney/Tencent/Sina).

- **Entry point**: `mobile/lib/main.dart`
- **Version**: `mobile/pubspec.yaml` + `mobile/lib/core/app_version.dart` (currently v2.50.0)
- **Python env**: `venv/` (akshare for concept data generation)

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

### 2. 完整工作流（开发 → 编译 → 测试 → 提交）

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: 开发环境准备                                           │
├─────────────────────────────────────────────────────────────────┤
│  git clone https://github.com/zhaoshuiqiang/stock.git           │
│  cd stock                                                       │
│  cd mobile && flutter pub get                                   │
│  flutter emulators --launch StockEmulator                       │
│  flutter run -d emulator-5554                                   │
├─────────────────────────────────────────────────────────────────┤
│  Step 2: 代码开发                                               │
├─────────────────────────────────────────────────────────────────┤
│  编辑 mobile/lib/ 下的文件                                      │
│  Hot reload: 保存文件或按 R 键                                   │
├─────────────────────────────────────────────────────────────────┤
│  Step 3: 运行测试                                               │
├─────────────────────────────────────────────────────────────────┤
│  cd mobile && flutter test                                      │
│  ✅ 全部通过后继续下一步                                         │
├─────────────────────────────────────────────────────────────────┤
│  Step 4: 编译 APK（使用 PowerShell 脚本）                        │
├─────────────────────────────────────────────────────────────────┤
│  powershell -File mobile/build_release.ps1                      │
│  输出: d:\MyProjects\stock\stock-vX.Y.Z.apk                     │
├─────────────────────────────────────────────────────────────────┤
│  Step 5: Git 提交                                               │
├─────────────────────────────────────────────────────────────────┤
│  git status                                                     │
│  git add mobile/lib/screens/xxx.dart mobile/pubspec.yaml ...    │
│  git commit -m "vX.Y.Z: Description"                            │
│  git push origin main                                           │
└─────────────────────────────────────────────────────────────────┘
```

### 3. 详细步骤说明

#### 3.1 开发环境准备

```bash
# 克隆仓库
git clone https://github.com/zhaoshuiqiang/stock.git
cd stock

# 安装依赖
cd mobile && flutter pub get

# 启动模拟器并运行应用
flutter emulators --launch StockEmulator
flutter run -d emulator-5554
```

#### 3.2 代码开发

- 编辑 `mobile/lib/` 目录下的文件
- Hot reload: 保存文件或在终端按 R 键
- 推荐使用 VS Code 配合 Flutter 插件开发

#### 3.3 运行测试

```bash
# 运行全部测试（674+ tests）
cd mobile && flutter test

# 运行单个测试文件
cd mobile && flutter test test/signal_engine_test.dart

# 运行测试并生成覆盖率报告
cd mobile && flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

**测试策略**

| Test Type | Coverage | Purpose |
|-----------|----------|---------|
| Unit Tests | 39 files, 674+ tests | Core algorithm logic |
| Integration Tests | TBD | UI flow validation |
| Emulator Testing | Manual | Visual verification |

#### 3.4 编译 APK（执行脚本）

**方法一：使用 PowerShell 脚本（推荐）**

```bash
powershell -File mobile/build_release.ps1
```

脚本功能：
1. 自动读取 `pubspec.yaml` 中的版本号
2. 执行 `flutter build apk --release`
3. 将生成的 APK 复制到项目根目录，命名为 `stock-vX.Y.Z.apk`
4. 显示 APK 文件大小

**方法二：手动编译**

```bash
# Build debug APK
cd mobile && flutter build apk

# Build release APK
cd mobile && flutter build apk --release

# Build app bundle for Google Play
cd mobile && flutter build appbundle
```

#### 3.5 Git 提交与推送

```bash
# 1. 查看状态，确认修改的文件
git status

# 2. 暂存文件（明确指定，避免 git add .）
git add mobile/lib/screens/discover_screen.dart mobile/pubspec.yaml ...

# 3. 提交（遵循版本号格式）
git commit -m "vX.Y.Z: Brief description of changes

- Detailed change 1
- Detailed change 2
- Detailed change 3"

# 4. 推送到远程
git push origin main
```

#### 3.6 代码审查

```bash
# 查看变更
git diff

# 使用 TRAE-code-review skill 进行结构化审查
# 重点关注：错误处理、空安全、性能、代码风格
```

**审查清单**

- [ ] 无死代码（未使用的变量/方法）
- [ ] 正确的错误处理（try/catch）
- [ ] 空安全合规
- [ ] 一致的命名规范
- [ ] 性能：无不必要的计算
- [ ] UI：一致的颜色和间距
- [ ] 版本号更新：pubspec.yaml + app_version.dart + update_log_screen.dart

### 4. 版本发布流程

**Step 1: 更新版本号（3个文件）**

```bash
# mobile/pubspec.yaml
version: X.Y.Z

# mobile/lib/core/app_version.dart
static const String version = 'X.Y.Z';

# mobile/lib/screens/update_log_screen.dart
Add new version entry to updates list
```

**Step 2: 测试并编译**

```bash
cd mobile && flutter test
powershell -File mobile/build_release.ps1
```

**Step 3: 提交并推送**

```bash
git add mobile/pubspec.yaml mobile/lib/core/app_version.dart mobile/lib/screens/update_log_screen.dart
git commit -m "vX.Y.Z: Version bump"
git push origin main
```

## Quick Reference Commands

```bash
# Install dependencies
cd mobile && flutter pub get

# Run tests
cd mobile && flutter test

# Build release APK
powershell -File mobile/build_release.ps1

# Start emulator
flutter emulators --launch StockEmulator

# Run app on emulator
cd mobile && flutter run -d emulator-5554

# Generate concept tags (Python)
python scripts/build_concept_tags.py
# Output: mobile/assets/concept_tags.json
```

## Architecture

### Analysis Pipeline (`signal_engine.dart` → `generateAnalysis()`)

```
API (K-line + Quotes)
  │
  ├─ 1. Signal Detection (signal_layer/signal_detector)
  │     Short/Medium/Long signals across KDJ/RSI/MA/MACD/BOLL/CCI/WR/Gaps/Candlesticks
  │
  ├─ 1a. Market Structure (market_structure_analyzer) — NEW v2.27
  │     5 types: bullTrend/bearTrend/consolidation/accumulation/distribution
  │
  ├─ 1b. Percentile Analysis (percentile_analyzer) — NEW v2.27
  │     PE/PB industry percentiles + RSI + Volume ranking
  │
  ├─ 2. Technical Scorer → 3. Realtime Scorer → 4. Confluence Scorer
  ├─ 4a. Capital Flow Analyzer
  ├─ 5. Comprehensive Scorer (7-dim weighted fusion, structure=10%)
  ├─ 6. Reason Generation
  ├─ 7. Risk Analyzer → 8. Opportunity Identifier → 9. Suggestion Generator
  ├─ 10. Mega Backtest (6 strategies, walk-forward validation)
  ├─ 11. Strategy Builder (short/long, structure-aware filtering)
  ├─ 12. Confidence Calculator (6-dim, adversarial validation)
  └─ 13. Trade Levels (ATR dynamic stop-loss, tiered take-profit)
```

### Key Data Flow

- **`AnalysisResult`** is the central output model — aggregates all sub-results
- **`ExploreResult`** is a flattened summary for batch scan display (DiscoverScreen)
- **`RecommendationTracker`** records snapshots when score ≥ 6, tracks 5/10/20-day returns
- **`ConceptTagProvider`** singleton loads `concept_tags.json` at startup
- **`MarketStructureAnalyzer`** uses existing ADX + MA alignment (no new data needed)

### Directory Map

| Directory | Purpose |
|-----------|---------|
| `mobile/lib/analysis/` | All analysis engines (18 files) |
| `mobile/lib/models/` | Data models — `stock_models.dart` is the single source |
| `mobile/lib/screens/` | UI pages (17 screens) |
| `mobile/lib/widgets/` | Reusable UI components |
| `mobile/lib/api/` | HTTP client + market context + WebSocket |
| `mobile/lib/storage/` | SQLite (database_service.dart, v8) |
| `mobile/lib/data/` | Static data providers (concept_tag_provider) |
| `mobile/lib/validators/` | Data validation pipeline |
| `mobile/lib/core/` | App version, navigator key, trading session |
| `scripts/` | Python utilities (build_concept_tags.py) |

### Database (SQLite v8)

Tables: `watchlist`, `alerts`, `archive_records`, `explore_results`, `opportunity_results`, `sector_pick_results`, `home_cache`, `recommendation_tracking` (v8).

Migrations follow `if (oldVersion < N)` pattern in `database_service.dart`.

### Testing

674+ tests across 39 test files in `mobile/test/`. Tests import from `mobile/lib/` directly — no special test setup needed.

### Key Conventions

- **New analysis modules**: Static utility classes (e.g., `MarketStructureAnalyzer.analyze()`)
- **Model fields**: Always nullable for backward compatibility, defaults in constructors
- **Error handling**: Defensive `try/catch` with `debugPrint` logging for non-critical paths
- **Colors**: Defined as `const _k*` at top of screen files; red=up, green=down (A股 convention)
- **Version bumps**: Update `pubspec.yaml`, `app_version.dart`, and `update_log_screen.dart` together
- **Plan files**: Stored in `docs/superpowers/plans/` and `docs/superpowers/specs/`

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

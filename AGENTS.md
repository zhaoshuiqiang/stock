# AGENTS

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

Flutter (Dart) A-share stock analysis Android app. Pure client-side rule engine — no backend server, no LLM/API calls. All technical analysis computed locally from K-line data fetched via public stock APIs (EastMoney/Tencent/Sina).

- **Entry point**: `mobile/lib/main.dart`
- **Version**: `mobile/pubspec.yaml` + `mobile/lib/core/app_version.dart` (currently v2.27.0)
- **Python env**: `venv/` (akshare for concept data generation)

## Commands

```bash
# Build release APK
cd mobile && flutter build apk --release
# Or use the PowerShell script (auto-names with version):
powershell -File mobile/build_release.ps1

# Install dependencies
cd mobile && flutter pub get

# Run tests
cd mobile && flutter test

# Run a single test file
cd mobile && flutter test test/signal_engine_test.dart

# Python: generate concept tags data
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

131+ tests across 14 test files in `mobile/test/`. Tests import from `mobile/lib/` directly — no special test setup needed.

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

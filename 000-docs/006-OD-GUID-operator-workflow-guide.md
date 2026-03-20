# 006-OD-GUID — Operator Workflow Guide: wild-test-flake-forensics

**Filing code:** OD-GUID
**Status:** v1 placeholder — content to be expanded as integration patterns are validated in practice

---

## Overview

This guide covers the day-to-day usage patterns for engineering teams integrating `wild-test-flake-forensics` into their CI workflows. It assumes the gem is installed and the reader has reviewed the configuration reference (`005-DR-REFF-configuration-reference.md`).

---

## Basic usage flow

The pipeline has five stages: parse, detect, analyze, triage, export. Each stage is independently instantiable.

```
CI test output files
       |
   [parse]          -- Parsers::RspecJson / JunitXml / MinitestJson
       |
  TestResult[]
       |
   [detect]         -- Detection::FlakeDetector
       |
  FlakeRecord[]     (no root causes yet)
       |
   [analyze]        -- Analysis::RootCauseAnalyzer
       |
  FlakeRecord[]     (with root_causes populated)
       |
   [triage]         -- Triage::Engine
       |
  TriageEntry[]     (sorted by severity_score desc)
       |
   [export]         -- Export::JsonExporter / MarkdownExporter / SummaryExporter
       |
    String output
```

### Minimal example

```ruby
require 'wild_test_flake_forensics'

# Collect results from multiple CI runs
all_results = []
Dir['ci_results/run-*.json'].each_with_index do |path, i|
  results = WildTestFlakeForensics::Parsers::RspecJson.parse(
    File.read(path),
    run_id: "run-#{i + 1}"
  )
  all_results.concat(results)
end

# Detect, analyze, triage
flakes   = WildTestFlakeForensics::Detection::FlakeDetector.new.detect(all_results)
analyzed = WildTestFlakeForensics::Analysis::RootCauseAnalyzer.new.analyze(flakes, all_results: all_results)
entries  = WildTestFlakeForensics::Triage::Engine.new.triage(analyzed)

# Export
puts WildTestFlakeForensics::Export::SummaryExporter.new.export(entries)
File.write('flake-report.md', WildTestFlakeForensics::Export::MarkdownExporter.new.export(entries))
File.write('flake-report.json', WildTestFlakeForensics::Export::JsonExporter.new.export(entries))
```

---

## Configuration examples

### Default (no configuration needed)

```ruby
# Uses minimum_runs: 3, flake_rate_threshold: 0.1
```

### Conservative (fewer, higher-confidence detections)

```ruby
WildTestFlakeForensics.configure do |config|
  config.minimum_runs = 10
  config.flake_rate_threshold = 0.2
end
```

### Sensitive (catch rare flakes early)

```ruby
WildTestFlakeForensics.configure do |config|
  config.minimum_runs = 3
  config.flake_rate_threshold = 0.05
end
```

### Emphasize failure volume in severity scoring

```ruby
WildTestFlakeForensics.configure do |config|
  config.severity_weights = { flake_rate: 1.0, failure_count: 3.0, trend: 1.0, confidence: 1.0 }
end
```

---

## Reading triage reports

### Summary export (plain text)

The `SummaryExporter` produces one header line and one line per flake:

```
FLAKE REPORT: 4 flaky test(s) — 1 critical, 2 high
[CRITICAL] loads user profile (45.0% flake, cause: external_dependency)
[HIGH] sends confirmation email (33.3% flake, cause: timing_dependent)
[HIGH] validates cart total (28.6% flake, cause: shared_state)
[LOW] renders 404 page (12.5% flake, cause: unknown)
```

The cause label is the primary root cause category (highest confidence). "unknown" means no signal was strong enough to reach the 0.15 confidence threshold.

### Markdown export

The `MarkdownExporter` produces a report with a Summary section (severity counts table) and a Flaky Tests section with one subsection per flake. Each subsection shows:
- Severity label and score
- File path and context
- Flake rate as a percentage (failures / total runs)
- Trend direction (worsening / stable / improving)
- Root causes with confidence percentages
- Suggested remediations (up to 6, drawn from the highest-confidence root causes)

### JSON export

The `JsonExporter` produces a structured payload:

```json
{
  "metadata": {
    "generated_at": "2024-03-15T10:00:00Z",
    "version": "0.1.0",
    "total_flakes": null
  },
  "summary": {
    "critical": 1,
    "high": 2,
    "medium": 1,
    "low": 0,
    "total": 4,
    "avg_flake_rate": 0.2975,
    "top_root_cause": "external_dependency"
  },
  "flakes": [ ... ]
}
```

Each entry in `flakes` is the `to_h` representation of a `TriageEntry`, including nested `test_identity`, `root_causes`, and `remediations`.

---

## Trend tracking across runs

To track trends across multiple pipeline invocations, keep a `History::Store` in memory and feed it records after each analysis:

```ruby
store = WildTestFlakeForensics::History::Store.new

# After each CI run:
engine = WildTestFlakeForensics::Triage::Engine.new(history_store: store)
analyzed.each { |record| store.record(record) }
entries = engine.triage(analyzed)
```

The Engine will include trend information (`:worsening`, `:stable`, `:improving`) in each `TriageEntry` when a `history_store` is provided. Without a store, all entries default to `:stable`.

**Note:** The store is in-memory. It does not persist across process restarts. For cross-session trend tracking, serialize and reload `store.all` between invocations.

---

## Parsing JUnit XML (for non-RSpec CI setups)

```ruby
xml_results = WildTestFlakeForensics::Parsers::JunitXml.parse(
  File.read('test-results/junit.xml'),
  run_id: ENV.fetch('CI_BUILD_NUMBER', nil)
)
```

JUnit XML is supported from any CI system that produces standard JUnit output (GitHub Actions, CircleCI, Jenkins, Buildkite, etc.).

---

## Parsing minitest JSON

```ruby
results = WildTestFlakeForensics::Parsers::MinitestJson.parse(
  File.read('test-results/minitest.json'),
  run_id: 'run-001'
)
```

Requires minitest-reporters or a compatible reporter that produces JSON with a `tests` or `results` key. Status field variants (`pass`, `passed`, `ok`, `fail`, `failed`, etc.) are all normalized automatically.

---

## Placeholder sections — to be expanded

The following sections will be added as integration patterns are validated in practice:

- Rake task template for weekly flake reports
- GitHub Actions integration example
- Slack notification formatting
- Filtering entries by minimum severity before export
- Cross-format run (mixing RSpec JSON and JUnit XML in the same analysis)
- Interpreting low-confidence root cause assignments
- When to adjust minimum_runs vs flake_rate_threshold

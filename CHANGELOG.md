# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] - 2026-03-19

Initial release. All 10 epics implemented.

### Added

**Epic 1 — Project scaffold and gem foundation**
- Gemspec with `wild-test-flake-forensics` name, version 0.1.0, Ruby >= 3.2 constraint, zero runtime dependencies
- Gemfile with rspec, rubocop, rubocop-rspec, and rexml development dependencies
- Rakefile with default rspec task
- Top-level `WildTestFlakeForensics` module with `configure`, `configuration`, and `reset_configuration!` class methods
- Error class hierarchy: `Error`, `ParseError`, `ConfigurationError`, `DetectionError`, `ExportError`
- RSpec spec_helper with `reset_configuration!` before hook for test isolation

**Epic 2 — Configuration system**
- `Configuration` class with four validated parameters: `minimum_runs`, `flake_rate_threshold`, `max_history_entries`, `severity_weights`
- Validated setters that raise `ConfigurationError` with descriptive messages on invalid input
- `freeze!` method that deep-freezes the severity_weights hash and then freezes the object, making configuration immutable after the configure block
- `VALID_SEVERITY_WEIGHT_KEYS` constant restricting accepted weight keys to `:flake_rate`, `:failure_count`, `:trend`, `:confidence`

**Epic 3 — Core domain models**
- `Models::TestIdentity` with `file_path`, `test_name`, `context` fields, stable `key` method, and full equality/hash support
- `Models::TestResult` with status validation (passed/failed/errored/skipped/pending), `run_id`, `timestamp`, `duration_ms`, `error_message`, `metadata`
- `Models::RootCause` with 8 categories (timing_dependent, order_dependent, shared_state, external_dependency, random_seed, resource_contention, timezone_locale, unknown) and confidence scoring
- `Models::FlakeRecord` with computed `flake_rate`, `failure_count`, `duration_variance`, `primary_root_cause`
- `Models::TriageEntry` with severity labels (critical/high/medium/low), `severity_score`, `remediations`, `trend`

**Epic 4 — Format parsers**
- `Parsers::Base` abstract base with shared helpers: `require_non_empty!`, `coerce_run_id`, `default_timestamp`, `build_identity`, `build_result`
- `Parsers::RspecJson` for `rspec --format json` output: extracts examples, maps status, reads exception.message, reads seed from metadata
- `Parsers::JunitXml` using REXML (stdlib) for standard JUnit XML: supports both `<testsuite>` and `<testsuites>` roots, maps failure/error/skipped elements
- `Parsers::MinitestJson` for minitest-reporters JSON: handles both `tests` and `results` root keys, normalizes all common status string variants
- All parsers raise `ParseError` on structurally invalid input; skip (not raise) on malformed individual entries

**Epic 5 — Flake detection**
- `Detection::Comparator` for grouping TestResult arrays by TestIdentity key, checking for both pass and fail outcomes, and computing flake rates
- `Detection::FlakeDetector` applying `minimum_runs` and `flake_rate_threshold` to produce FlakeRecord objects from qualifying groups
- Both parameters readable from global configuration with per-instance constructor override support

**Epic 6 — Root cause analysis**
- `Analysis::SignalExtractors` mixin with six signal extraction methods: timing (coefficient of variation on durations), shared state (co-flake density in same file/context), external dependency (regex pattern matching on error messages), random seed (metadata seed divergence), resource contention (failure clustering in high-failure runs), timezone/locale (regex pattern matching)
- Pattern constants: `EXTERNAL_PATTERNS`, `TIMEZONE_PATTERNS`, `SEED_PATTERNS`
- `Analysis::RootCauseAnalyzer` orchestrating signal extraction, filtering at `CONFIDENCE_THRESHOLD` (0.15), and falling back to `:unknown` category when no signal qualifies
- All signals normalized to [0.0, 1.0] range; multiple root causes produced per flake sorted by descending confidence

**Epic 7 — Triage and severity scoring**
- `Triage::SeverityScorer` computing weighted scores from flake_rate, log-scaled failure_count, trend multiplier, and top root cause confidence
- Severity thresholds: critical >= 0.75, high 0.5-0.75, medium 0.25-0.5, low < 0.25
- `TREND_MULTIPLIERS` constants: worsening=0.9, stable=0.5, improving=0.1
- `Triage::Remediation` with curated 4-suggestion lists for all 8 root cause categories; `all_suggestions_for` merges top-N categories and deduplicates up to 6 suggestions
- `Triage::Engine` orchestrating scoring, trend fetching from optional History::Store, and TriageEntry construction sorted by descending severity_score

**Epic 8 — History and trend analysis**
- `History::Store` as in-memory hash with record (upsert/merge), fetch, all, trend_for, size, and clear! operations
- Per-key snapshot ring buffer (last 50 flake rate observations) for trend computation
- `max_entries` cap with oldest-first eviction via `enforce_limit!`
- `History::TrendAnalyzer` with half-split delta algorithm: computes average flake rate in the first half vs second half of sorted snapshots; returns `:worsening`, `:stable`, or `:improving`
- Thresholds: worsening at delta >= 0.05, improving at delta <= -0.05

**Epic 9 — Export**
- `Export::JsonExporter` producing a JSON document with metadata (generated_at, version), summary (severity counts, total, avg_flake_rate, top_root_cause), and full flakes array
- `Export::MarkdownExporter` producing a Markdown report with summary table and per-flake sections showing severity, file, context, flake rate, trend, root causes with confidence percentages, and remediation bullets; escapes pipe and backtick characters in test names
- `Export::SummaryExporter` producing a CI-friendly single-header line plus one line per flake showing severity, truncated test name, flake rate, and primary cause
- All exporters raise `ExportError` on non-Array input

**Epic 10 — Adversarial testing and hardening**
- `spec/adversarial/malformed_input_spec.rb` covering nil, empty, whitespace, truncated, wrong-structure, and missing-key inputs for all three parsers
- `spec/adversarial/edge_cases_spec.rb` covering special characters in test names (quotes, brackets, pipes, backticks, newlines, unicode), large result sets (1000 results with performance guard < 5s), boundary conditions, adversarial filenames (path traversal strings, very long paths), history store pressure (max_entries enforcement), and configuration freeze enforcement
- `spec/integration/full_pipeline_spec.rb` covering end-to-end pipeline with multiple export formats, stable test exclusion, empty pipeline, and root cause assignment
- `spec/integration/multi_format_spec.rb` covering cross-parser consistency
- 277 examples, 0 failures; 55 files inspected, 0 RuboCop offenses

---

[0.1.0]: https://github.com/jeremylongshore/wild-test-flake-forensics/releases/tag/v0.1.0

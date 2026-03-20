# 002-PP-PLAN — Epic Build Plan: wild-test-flake-forensics

**Filing code:** PP-PLAN
**Status:** v1 — all 10 epics implemented
**Note:** This document was written post-implementation to canonicalize what was built and the narrative of how it came together.

---

## Overview

The gem was built in 10 epics following a pipeline architecture: scaffold the project structure, build normalized models, implement format parsers, detect flakes, analyze root causes, triage and score severity, track history and trends, export results, harden with adversarial tests, and complete the release. Each epic built cleanly on the one before it.

---

## Epic 1: Project scaffold and gem foundation

**Mission:** Establish the gem skeleton with correct Ruby/gem conventions so all subsequent work has a clean foundation.

**Scope:**
- Gemspec with name, version, authors, description, Ruby version constraint (>= 3.2)
- Gemfile with dev/test dependencies (rspec, rubocop, rubocop-rspec, rexml)
- Rakefile with default rspec task
- Top-level module `WildTestFlakeForensics` with configure/configuration/reset_configuration! interface
- `VERSION = '0.1.0'`
- Error class hierarchy: `Error`, `ParseError`, `ConfigurationError`, `DetectionError`, `ExportError`
- RSpec spec_helper with reset_configuration! before hook
- `.rubocop.yml` configuration

**Out of scope:** Any domain logic. This epic is purely structural.

**Child task themes:** Gemspec setup, Gemfile dependencies, module entry point, error hierarchy, spec infrastructure, RuboCop baseline.

**Dependency notes:** No dependencies. All other epics depend on this.

**Narrative:** The gem starts as almost nothing — a name, a module, and a well-formed skeleton. The decision to use `freeze!` on configuration after the configure block was made here, keeping mutation errors early and explicit. The error hierarchy was sketched in full so each domain subsystem could raise domain-specific errors without coupling to each other.

---

## Epic 2: Configuration system

**Mission:** Provide a validated, immutable-after-configure configuration object that all components can read without coupling to each other.

**Scope:**
- `Configuration` class with four parameters: `minimum_runs`, `flake_rate_threshold`, `max_history_entries`, `severity_weights`
- Validated setters that raise `ConfigurationError` with descriptive messages on invalid input
- `freeze!` method that deep-freezes the severity_weights hash and then freezes the object
- `VALID_SEVERITY_WEIGHT_KEYS` constant restricting which weight keys are accepted
- Full spec coverage including boundary cases, invalid types, and freeze behavior

**Out of scope:** Any component that reads configuration. That happens in subsequent epics.

**Child task themes:** Parameter types and defaults, setter validation, freeze! behavior, ConfigurationError messages, spec coverage.

**Dependency notes:** Depends on Epic 1. Detection, Triage, and History components depend on this.

**Default values:**
- `minimum_runs`: 3
- `flake_rate_threshold`: 0.1
- `max_history_entries`: 10,000
- `severity_weights`: `{ flake_rate: 1.0, failure_count: 1.0, trend: 1.0, confidence: 1.0 }`

**Narrative:** Configuration is the contract the whole library is built against. Getting validation right here meant every downstream component could trust its inputs without defensive checks. The `freeze!` pattern was chosen over lazy immutability because configuration should be wrong early, not at runtime inside a tight loop.

---

## Epic 3: Core domain models

**Mission:** Define the normalized data model that the entire pipeline passes around, ensuring all components speak the same language regardless of input format.

**Scope:**
- `Models::TestIdentity` — stable key for a test across runs (file_path, test_name, context). Implements `==`, `eql?`, `hash`, `key`, `to_s`, `to_h`.
- `Models::TestResult` — a single test run outcome. Statuses: passed, failed, errored, skipped, pending. Carries duration_ms, error_message, metadata hash, run_id, timestamp.
- `Models::RootCause` — a confidence-scored hypothesis. Categories: timing_dependent, order_dependent, shared_state, external_dependency, random_seed, resource_contention, timezone_locale, unknown. Carries evidence array, description.
- `Models::FlakeRecord` — a test's complete flake history. Computed: flake_rate, total_runs, failure_count, pass_count, duration_variance, primary_root_cause.
- `Models::TriageEntry` — a fully triaged flake. Carries severity (critical/high/medium/low), severity_score, remediations, trend.
- Full validation in constructors with ArgumentError on invalid input
- Full spec coverage for all models

**Out of scope:** Logic that creates or transforms these models. That belongs to parsers, detection, analysis, and triage.

**Child task themes:** TestIdentity equality and hashing, TestResult status validation, RootCause confidence thresholds, FlakeRecord computed fields, TriageEntry severity levels, model serialization (to_h).

**Dependency notes:** Depends on Epic 1. All other epics depend on these models.

**Narrative:** The models are the language the pipeline speaks. Getting them right — especially TestIdentity's `key` method as the canonical grouping mechanism — is what makes the detection and history subsystems simple. FlakeRecord.duration_variance (using standard deviation) was added here because timing signal extraction needed it.

---

## Epic 4: Format parsers

**Mission:** Ingest CI test output in three formats and normalize it to TestResult objects, handling malformed or partially valid input gracefully.

**Scope:**
- `Parsers::Base` — abstract base with `require_non_empty!`, `coerce_run_id`, `default_timestamp`, `build_identity`, `build_result` helpers
- `Parsers::RspecJson` — parses `--format json` RSpec output. Extracts examples array, maps status, extracts exception.message, extracts seed from metadata.
- `Parsers::JunitXml` — parses JUnit XML using REXML (stdlib). Handles both `<testsuite>` and `<testsuites>` roots. Maps failure/error/skipped child elements to status.
- `Parsers::MinitestJson` — parses minitest-reporters JSON. Handles both `tests` and `results` root keys. STATUS_MAP covers all common string variants.
- Invalid input raises `ParseError`. Invalid individual examples/test cases are skipped (not raised).
- Both class-method and instance-method `parse` interfaces.

**Out of scope:** Detection logic. Parsers only produce TestResult arrays.

**Child task themes:** Base class helpers, RSpec JSON mapping, JUnit XML XPath traversal, minitest status normalization, nil/empty input handling, graceful skip of malformed individual entries.

**Dependency notes:** Depends on Epics 1-3.

**Narrative:** The parsers had to handle the reality of CI output: partially formed documents, missing fields, wrong root elements, and inconsistent field names across minitest reporter plugins. The design decision to skip (not raise) on malformed individual test entries while raising on structurally invalid documents was deliberate — a document with 3 broken examples and 97 valid ones should still produce 97 results.

---

## Epic 5: Flake detection

**Mission:** Identify which tests are flaky by grouping results by test identity across runs and applying configurable detection thresholds.

**Scope:**
- `Detection::Comparator` — groups TestResult arrays by TestIdentity key, checks for both outcomes, computes flake rate. Available as both class method and instance method.
- `Detection::FlakeDetector` — applies minimum_runs and flake_rate_threshold to decide which groups qualify as flakes. Produces FlakeRecord objects (without root causes at this stage).
- Reads minimum_runs and flake_rate_threshold from configuration (with override via constructor).
- Raises `DetectionError` on non-Array input.

**Out of scope:** Root cause analysis. This epic only decides "is this test flaky?", not "why?".

**Child task themes:** Grouping by identity key, both_outcomes? check, flake rate calculation, minimum runs guard, threshold application, empty input handling.

**Dependency notes:** Depends on Epics 1-4.

**Narrative:** Detection is intentionally simple: group, check both outcomes, check rate, check run count. The `both_outcomes?` check is the core invariant — a test that only ever fails is broken, not flaky. The threshold and minimum runs are the two dials that determine sensitivity. Keeping detection separate from analysis made both parts testable in isolation.

---

## Epic 6: Root cause analysis

**Mission:** Examine FlakeRecord observations and produce confidence-scored root cause hypotheses by extracting and weighing observable signals.

**Scope:**
- `Analysis::SignalExtractors` — mixin module implementing six signal extraction methods:
  - `timing_signal` — coefficient of variation on durations
  - `shared_state_signal` — co-flake density in same file/context
  - `external_dependency_signal` — regex match rate on EXTERNAL_PATTERNS in error messages
  - `random_seed_signal` — seed divergence between pass/fail runs from metadata
  - `resource_contention_signal` — failure clustering in high-failure runs
  - `timezone_locale_signal` — regex match rate on TIMEZONE_PATTERNS
- Pattern constants: EXTERNAL_PATTERNS, TIMEZONE_PATTERNS, SEED_PATTERNS
- `Analysis::RootCauseAnalyzer` — orchestrates signal extraction, filters by CONFIDENCE_THRESHOLD (0.15), sorts by descending confidence, falls back to `unknown` category if no signal qualifies.
- Produces new FlakeRecord objects with root_causes populated.
- Takes optional `all_results:` for cross-run resource contention analysis.

**Out of scope:** Severity scoring, remediation suggestions. This epic only produces hypotheses.

**Child task themes:** Signal extraction methods, pattern constants, confidence normalization, CONFIDENCE_THRESHOLD filtering, fallback to unknown, `all_results` cross-run context, evidence string generation.

**Dependency notes:** Depends on Epics 1-5.

**Narrative:** The signal extraction module is the forensics core. Each signal is independently extracted and confidence-normalized to [0.0, 1.0]. Signals below 0.15 are discarded to avoid noise. The choice to produce multiple hypotheses per flake (sorted by confidence) rather than a single classification reflects the reality that flakes often have multiple contributing causes. The `unknown` fallback with confidence 0.5 ensures every flake gets actionable output.

---

## Epic 7: Triage and severity scoring

**Mission:** Produce a prioritized, actionable triage list from analyzed FlakeRecord objects, with severity labels, weighted scores, trend awareness, and per-flake remediation suggestions.

**Scope:**
- `Triage::SeverityScorer` — computes a weighted score from four components: flake_rate, failure_count (log-scaled), trend multiplier, top root cause confidence. Score buckets: critical (>=0.75), high (0.5-0.75), medium (0.25-0.5), low (<0.25). Reads severity_weights from configuration.
- `Triage::Remediation` — maps root cause categories to curated lists of 4 remediation suggestions per category. `suggestions_for` returns primary category suggestions. `all_suggestions_for` merges all categories' suggestions (sorted by confidence, up to 6 unique items).
- `Triage::Engine` — orchestrates scoring, fetches trends from optional History::Store, builds TriageEntry objects, sorts by descending severity_score.
- TREND_MULTIPLIERS: worsening: 0.9, stable: 0.5, improving: 0.1

**Out of scope:** Export formatting. This epic produces TriageEntry objects, not strings.

**Child task themes:** Score formula, log-scaled failure count, trend multiplier constants, severity bucketing thresholds, remediation map, all_suggestions_for deduplication, Engine orchestration, History::Store integration hook.

**Dependency notes:** Depends on Epics 1-6. History integration is optional (nil history_store defaults to :stable trend).

**Narrative:** The severity score formula was designed to capture both "how bad is this right now" (flake_rate, failure_count) and "how confident are we" (confidence) and "is it getting worse" (trend). Log-scaling the failure count prevents a test that fails 1000 times from dominating over one that fails 5 times but at 90% flake rate. The remediation map was written with specificity — not "fix your test" but "Add before/after hooks to reset shared state" or "Set ENV[TZ] = UTC in test configuration".

---

## Epic 8: History and trend analysis

**Mission:** Track flake records across multiple pipeline runs and detect whether a flake is worsening, stable, or improving over time.

**Scope:**
- `History::Store` — in-memory hash of test identity keys to FlakeRecord. Supports record (upsert with merge), fetch, all, trend_for, size, clear!. Maintains a per-key snapshot ring buffer (last 50 flake rate observations). Enforces max_entries cap with oldest-first eviction.
- `History::TrendAnalyzer` — compares average flake rate in the first half vs second half of snapshots. Returns :worsening if delta >= 0.05, :improving if delta <= -0.05, :stable otherwise. Also exposes `trend_from_rates` for testing without timestamp objects.
- Reads max_history_entries from configuration.

**Out of scope:** Persistence. The store is purely in-memory and starts empty on every process.

**Child task themes:** Record merge logic (dedup results, take latest root_causes, expand first/last seen), snapshot ring buffer, eviction at cap, trend computation, half-split delta algorithm.

**Dependency notes:** Depends on Epics 1-3. Used optionally by Triage::Engine (Epic 7).

**Narrative:** The store was designed to be the simplest in-memory accumulator that could answer "is this flake getting worse?" It does not try to be a database. The half-split trend algorithm is simple and stable: it doesn't depend on linear regression or window functions, just the average of the older half versus the newer half. The 50-snapshot cap per test prevents unbounded memory growth at the snapshot level independently of the max_entries cap at the record level.

---

## Epic 9: Export

**Mission:** Serialize triage results to three output formats suitable for different consumption contexts: machine-readable JSON, human-readable Markdown, and CI-friendly plain text summary.

**Scope:**
- `Export::JsonExporter` — produces a JSON document with metadata (generated_at, version), summary (severity counts, total, avg_flake_rate, top_root_cause), and full flakes array (each entry via to_h). Raises ExportError on JSON generation failure.
- `Export::MarkdownExporter` — produces a Markdown report with header, summary table, and per-flake sections. Each section shows severity, file, context, flake rate, trend, root causes with confidence percentages, and remediation bullets. Escapes `|` and backtick in test names.
- `Export::SummaryExporter` — produces a single-paragraph plain-text summary line plus one line per flake showing severity, truncated test name (60 chars), flake rate, and primary cause. Designed for CI log output and Slack messages.
- All exporters raise ExportError on non-Array input.

**Out of scope:** Writing to files or HTTP endpoints. Exporters return strings; calling code handles I/O.

**Child task themes:** JSON payload structure, Markdown section rendering, summary line format, severity breakdown, avg_flake_rate calculation, special character escaping in Markdown, empty results handling.

**Dependency notes:** Depends on Epics 1-3, 7. Exporters consume TriageEntry arrays.

**Narrative:** Three export formats serve three different audiences. JSON is for dashboards and downstream tooling. Markdown is for wiki pages, PR comments, and team reports. Summary is for CI scripts that need to print a report to stdout before exiting. The decision to return strings rather than write files directly keeps the exporters testable and composable — the calling code decides where output goes.

---

## Epic 10: Adversarial testing and hardening

**Mission:** Verify that the library handles malformed input, edge cases, adversarial filenames, and resource pressure without crashing, exposing unexpected behavior, or growing without bound.

**Scope:**
- `spec/adversarial/malformed_input_spec.rb` — ParseError coverage for nil, empty, whitespace, truncated JSON, wrong root structure, missing required keys across all three parsers. Graceful skip for malformed individual entries.
- `spec/adversarial/edge_cases_spec.rb` — special characters in test names (quotes, brackets, pipes, backticks, newlines, unicode), large result sets (1000 results, performance guard < 5s), boundary conditions (exactly minimum_runs, zero duration, nil duration_ms, all-skipped results), adversarial filenames (path traversal strings, very long paths, unicode paths), history store pressure (max_entries enforcement), configuration freeze enforcement.
- `spec/integration/full_pipeline_spec.rb` — end-to-end pipeline exercises: detect + analyze + triage + export (all three formats), stable test exclusion, empty pipeline, root cause assignment.
- `spec/integration/multi_format_spec.rb` — cross-parser consistency: same test data through RSpec JSON, JUnit XML, and minitest JSON produces comparable results.

**Out of scope:** Property-based testing, fuzzing, performance benchmarking beyond basic sanity guards.

**Child task themes:** ParseError assertions per parser, graceful skip behavior, special character handling, large dataset performance, boundary condition correctness, adversarial filename safety, history eviction, config immutability.

**Dependency notes:** Depends on all prior epics.

**Narrative:** Adversarial tests were the final confirmation that the design was sound. Path traversal strings in file_path fields pass through safely because the library never reads files — it just stores and compares strings. Malformed XML and JSON raise ParseError cleanly. Large result sets run in well under 5 seconds. All boundary conditions that were assumed correct during implementation were verified explicitly. The result: 277 examples, 0 failures, 0 RuboCop offenses.

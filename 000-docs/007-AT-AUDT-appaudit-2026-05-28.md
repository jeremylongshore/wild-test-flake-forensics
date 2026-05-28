# 007-AT-AUDT — Operator Audit: wild-test-flake-forensics

**Filing code:** AT-AUDT
**Date:** 2026-05-28
**Auditor:** appaudit (operator-grade system analysis)
**Subject:** `wild-test-flake-forensics` v0.1.0
**Audience:** senior Rails/Ruby engineer, first read, 10 min to operate
**Status:** v1 complete — 10 epics, 277 tests passing, 0 RuboCop offenses

---

## 1. Mission and Boundaries

`wild-test-flake-forensics` is a pure Ruby library gem (no runtime dependencies, no CLI, no MCP server, no network surface) that consumes test run output from CI and emits ranked, root-cause-annotated triage reports describing which tests are flaky and why they probably are. It is one of ten repos in the `wild/` ecosystem and falls into Archetype C — SDLC Companion. It is a tool engineers run, not a runtime an agent calls.

**A flake, as this gem defines it,** is a `(file_path, context, test_name)` triple that has been observed at least `minimum_runs` times (default 3), has produced *both* a `:passed` outcome and at least one `:failed`/`:errored` outcome across those runs, and whose `failures / total_runs` ratio meets or exceeds `flake_rate_threshold` (default 0.10). This is the entire definition. See `lib/wild_test_flake_forensics/detection/flake_detector.rb:24-36` and `detection/comparator.rb:22-34`. A test that always fails is not a flake (it is broken). A test that has never failed is not a flake (it is stable). A test that has failed once in two observed runs is not a flake (insufficient data).

**In scope:**

| Capability | Code location |
|---|---|
| Parse RSpec JSON, JUnit XML, minitest JSON | `lib/wild_test_flake_forensics/parsers/` |
| Group results by stable test identity | `models/test_identity.rb` (key = `file_path::context::test_name`) |
| Detect flaky tests by threshold | `detection/flake_detector.rb` |
| Score six root-cause hypotheses with confidence | `analysis/root_cause_analyzer.rb`, `analysis/signal_extractors.rb` |
| Severity score + four-tier classification | `triage/severity_scorer.rb` |
| Remediation suggestions per cause | `triage/remediation.rb` (lookup table, no inference) |
| Bounded in-memory trend tracking | `history/store.rb`, `history/trend_analyzer.rb` |
| Export JSON, Markdown, summary text | `export/` |

**Out of scope (by explicit design decision, not omission):**

- Executing tests, invoking shell, or spawning subprocesses. This is enforced as Safety Rule 1 in `000-docs/003-TQ-STND-safety-model.md`. There are zero calls to `system`, `exec`, `Open3`, `popen`, or backticks in `lib/`.
- Reading files derived from `TestIdentity.file_path`. The path is metadata for display only; path-traversal-looking values like `../../../etc/passwd` are stored as opaque strings (see `spec/adversarial/edge_cases_spec.rb:141-145`).
- Network I/O of any kind. No HTTP, no sockets, no DNS.
- Persistence. The `History::Store` is a Hash in memory, capped, and discarded on process exit (Decision 2 in `004-AT-ADEC`).
- Automatically fixing flaky tests. The gem produces hypotheses and links to remediation playbooks; humans act on them.
- Polling CI, calling GitHub Actions, or owning a schedule. Caller-supplied input only.

The gem refuses to be a runtime service. That refusal is the load-bearing safety property: there is nothing here for a compromised CI job to abuse beyond memory and CPU.

---

## 2. Detection Architecture

Detection is deliberately statistical and shallow. The gem makes no claim to ML, no claim to model-based inference; it composes a handful of explicit signals into a confidence number and ranks the result. Five layers cooperate:

### 2.1 Parser layer (`parsers/`)

Three parsers — `RspecJson`, `JunitXml`, `MinitestJson` — all subclass `parsers/base.rb` and normalize their input into a homogeneous stream of `Models::TestResult` objects. After normalization, no downstream component knows or cares what format the data came from (Decision 5 in `004-AT-ADEC`). Each parser is responsible for:

- Mapping its native status vocabulary (`pass`/`passed`/`ok` → `:passed`; `fail`/`failure`/`failed` → `:failed`; etc.) — see `MinitestJson::STATUS_MAP` and `RspecJson#map_status`.
- Building a `TestIdentity` from format-specific fields (`file_path`/`location` for RSpec; `classname`+`name` for JUnit; `file`/`class` for minitest).
- Extracting `error_message`, `duration_ms`, and metadata where present.
- Rejecting structurally invalid input with `ParseError`, while *skipping* invalid individual entries inside an otherwise valid document (`filter_map` + `rescue ArgumentError`). This is the explicit Safety Rule 2 behavior.

The parser layer is the only place format-specific knowledge lives. Adding a fourth format (pytest, TAP) means implementing `Parsers::Base#parse` and nothing else.

### 2.2 Comparator and identity grouping (`detection/comparator.rb`)

`Comparator#group_by_identity` is the heart of the flake question. It buckets a flat list of `TestResult`s by `test_identity.key` (the `file_path::context::test_name` triple). The key is stable across runs because all three components are frozen strings on the identity object. `both_outcomes?(results)` answers "did we see this test both pass and fail" by inspecting unique statuses. `flake_rate(results)` is `failures.to_f / size` — no smoothing, no Laplace correction, no Bayesian prior.

### 2.3 Detection threshold (`detection/flake_detector.rb`)

`FlakeDetector#detect` walks each group and emits a `FlakeRecord` only when all three gates pass:

1. `group.size >= minimum_runs` (default 3)
2. `comparator.both_outcomes?(group)` (saw both pass and fail)
3. `comparator.flake_rate(group) >= flake_rate_threshold` (default 0.10)

There is no statistical-significance test, no confidence interval on the flake rate itself. The thresholds are operator-set thumbs on the scale.

### 2.4 Root cause analysis (`analysis/`)

`RootCauseAnalyzer#analyze` takes the detected `FlakeRecord`s plus the full `all_results` corpus (needed for cross-record signals like shared-state and resource-contention) and, for each record, computes six independent confidence scores using `SignalExtractors`:

| Signal | What it measures | Code |
|---|---|---|
| `timing_signal` | Coefficient of variation of `duration_ms` (stddev/mean), scaled ×1.5, clamped [0,1] | `signal_extractors.rb:22` |
| `shared_state_signal` | Max(file-sharing score, context-sharing score) — counts other flakes in same file/context | `signal_extractors.rb:34` |
| `external_dependency_signal` | Fraction of error messages matching `EXTERNAL_PATTERNS` regex (network, timeout, http, db, api, socket, dns, ECONNREFUSED, Net::) | `signal_extractors.rb:41` |
| `random_seed_signal` | Distinct seeds in metadata; 0.8 if failure-seeds and pass-seeds disjoint, 0.3 if they overlap | `signal_extractors.rb:49` |
| `resource_contention_signal` | Average count of co-failing tests in the runs where this test failed, ×0.05, capped at 0.7 | `signal_extractors.rb:64` |
| `timezone_locale_signal` | Fraction of error messages matching `TIMEZONE_PATTERNS` (timezone, locale, utc, dst, strftime, ActiveSupport::TimeZone) | `signal_extractors.rb:75` |

Scores below `CONFIDENCE_THRESHOLD = 0.15` are dropped. If all six fall below, a synthetic `:unknown` cause with confidence 0.5 is attached so the record never has an empty `root_causes` array. Surviving causes are sorted by confidence descending. The signals are independent — there is no co-variance term, no normalization across hypotheses, and the same flake can carry three or four causes at meaningful confidence simultaneously. This is intentional (Decision 4): flakes commonly have multiple contributing factors and a single-label classifier would be overconfident.

### 2.5 Trend layer (`history/trend_analyzer.rb`)

A trend is computed only when a `History::Store` is wired into the triage `Engine`. The store keeps a ring buffer of up to 50 `{rate, at}` snapshots per test identity. `TrendAnalyzer#trend` splits the sorted snapshots in half, takes the mean rate of each half, and classifies the delta: `>= +0.05 → :worsening`, `<= -0.05 → :improving`, else `:stable`. This is a moving-average comparison, not a regression — no slope, no significance, just two windows and a threshold.

---

## 3. The Critical Path

Take one CI run that produced a flake. Follow it end-to-end.

Input: an RSpec JSON file from the third of three CI runs, the previous two already on disk. The flaky test is `UserController#loads user profile`, which has passed twice and failed once.

```ruby
# 1. PARSE — file → TestResult[]
results = Dir['ci_results/run-*.json'].each_with_index.flat_map do |path, i|
  WildTestFlakeForensics::Parsers::RspecJson.parse(File.read(path), run_id: "run-#{i+1}")
end
# parsers/rspec_json.rb#parse → parse_json! → validate_rspec_format! →
# extract_examples → build_result_from_example for each example.
# Each example becomes one TestResult; identity key = file_path::context::test_name.
```

```ruby
# 2. DETECT — TestResult[] → FlakeRecord[]
flakes = WildTestFlakeForensics::Detection::FlakeDetector.new.detect(results)
# flake_detector.rb#detect → comparator.group_by_identity →
# build_flake_record gates: size >= 3, both_outcomes?, flake_rate >= 0.1.
# Our test: size=3 (pass), both_outcomes?=true (pass), 1/3 = 0.333 >= 0.1 (pass).
# Output: FlakeRecord with results=[3 results], no root_causes yet.
```

```ruby
# 3. ANALYZE — FlakeRecord[] + all results → FlakeRecord[] with root_causes
analyzed = WildTestFlakeForensics::Analysis::RootCauseAnalyzer.new
  .analyze(flakes, all_results: results)
# root_cause_analyzer.rb#analyze → group_by_run → build_root_causes:
#   timing_cause (CV of durations)
#   shared_state_cause (other flakes in same file)
#   external_dependency_cause (error message matches EXTERNAL_PATTERNS)
#   random_seed_cause (seed disjointness)
#   resource_contention_cause (co-failing tests in failed-runs)
#   timezone_locale_cause (error message matches TIMEZONE_PATTERNS)
# Causes scoring >= 0.15 survive, sorted by confidence desc. None? → :unknown@0.5.
# A FlakeRecord is REBUILT (not mutated) with causes attached.
```

```ruby
# 4. TRIAGE — FlakeRecord[] → TriageEntry[] (sorted by severity)
entries = WildTestFlakeForensics::Triage::Engine.new.triage(analyzed)
# triage/engine.rb#triage → build_entry per record:
#   trend := history_store ? history_store.trend_for(identity) : :stable
#   score := SeverityScorer#score(record, trend:)
#     weighted average of [flake_rate, log10(failures)/3, trend_multiplier, top_confidence]
#   severity := severity_from_score(score)
#     >=0.75 critical, >=0.5 high, >=0.25 medium, else low
#   remediations := Remediation#all_suggestions_for(root_causes)
#     dedup up to 6 suggestions, drawn highest-confidence-cause-first
# Entries sorted by severity_score descending.
```

```ruby
# 5. EXPORT — TriageEntry[] → String
md = WildTestFlakeForensics::Export::MarkdownExporter.new.export(entries)
# export/markdown_exporter.rb renders: header, severity-count summary table,
# per-entry section with severity, file, flake rate, trend, ranked causes,
# remediation bullets.
```

The whole pipeline is five method calls. Every intermediate type (`TestResult`, `FlakeRecord`, `RootCause`, `TriageEntry`) is immutable after construction. Every component is independently instantiable, takes its inputs explicitly, and produces a typed return value. There is no hidden global state apart from `WildTestFlakeForensics.configuration`, which is frozen after `configure {}` completes.

---

## 4. Integration with CI

**What this gem consumes:** standardized test reporter output as a string in memory. The caller is responsible for getting that string into the process.

| Format | Reporter | Field validated |
|---|---|---|
| RSpec JSON | `rspec --format json` | top-level `examples` key (Array) |
| JUnit XML | any CI emitting `<testsuite>`/`<testsuites>` | root element name |
| minitest JSON | minitest-reporters JSON format | top-level `tests` or `results` key |

**What this gem does NOT consume:** GitHub Actions API responses, raw CI log output, screenshots, video, console-only reporter dumps. If your reporter is "dots and Fs," install a JSON or JUnit reporter first.

**There is no integration helper, Rake task generator, CLI binary, or GitHub Action.** The `006-OD-GUID` operator guide acknowledges this directly in its "Placeholder sections — to be expanded" list: Rake task templates, GitHub Actions examples, and Slack formatting are all stubbed as future work. The README's "Quick start" is the entire integration contract: the caller writes ~10 lines of Ruby that read files, call five gem methods in sequence, and write the result.

**The expected wire pattern** is a CI job that, after a run, downloads the previous N run artifacts, calls `Dir['ci_results/run-*.json'].flat_map { Parsers::RspecJson.parse(...) }`, runs the pipeline, and writes `flake-report.md` as a build artifact or PR comment. None of that orchestration is in the gem. It is *unclear from the current code* whether the operator is expected to wire artifact rotation, GitHub Actions matrix output collection, or PR-comment plumbing themselves — the operator guide promises examples and does not yet provide them. This is the largest documentation gap (see Recommendations).

**Cross-repo CI:** `.github/workflows/ci.yml` runs `bundle exec rspec` and `bundle exec rubocop` on Ruby 3.2 and 3.3. The gem's own CI does not invoke the gem against the gem's own test history — the gem is not yet dogfooded.

---

## 5. Failure Modes and Blast Radius

The gem is fail-safe by archetype: no network surface, no execution surface, no persistence. The realistic failure modes are correctness failures, not blast-radius events.

| Failure mode | Mechanism | Operator impact | Mitigation in code |
|---|---|---|---|
| **False positive — stable test flagged** | A test that genuinely failed once due to an infra outage during one of 3 observed runs hits `flake_rate ≥ 0.1`, gets flagged. | Engineers chase a non-flake; trust in the report degrades. | Raise `minimum_runs` (5–10) and/or `flake_rate_threshold` (0.2). Conservative-preset is documented in `006-OD-GUID`. |
| **False negative — real flake missed** | Test fails once in 50 runs (`rate = 0.02 < 0.10`); detector silent. | Long-tail flakes accumulate. | Lower `flake_rate_threshold` to 0.02. Tradeoff: more false positives. |
| **False negative — first observation** | A test seen only twice (`size < minimum_runs=3`) never qualifies. | Newly-added flaky tests invisible until they recur. | Lower `minimum_runs` to 2. Tradeoff: one-off failures look like flakes. |
| **Classifier overconfidence — root cause** | `random_seed_signal` returns hardcoded `0.8` when failure-seeds and pass-seeds are fully disjoint (`signal_extractors.rb:59`). Two failed runs with different seeds and one passed run with another seed = 0.8 confidence on "random seed" with three data points. | Misleading remediation: "pin the seed" suggested when the real cause is timing. | Treat any single root cause as a hypothesis. The remediation engine emits *up to 6* suggestions across the top causes, so the operator sees other possibilities even when one signal dominates. |
| **Classifier overconfidence — external** | Any error containing `"timeout"` matches `EXTERNAL_PATTERNS`. A timing-flake whose error happens to say "operation timed out" is mis-classified as external dependency. | Wrong remediation surface. | None in v1. Patterns are case-insensitive regex, no context awareness. |
| **Report explosion under high flake rate** | A suite where 30% of tests are flaky produces a markdown report with hundreds of entries; the JSON payload includes all `TriageEntry#to_h` (root_causes + remediations) per entry. | Reports become unreadable; PR comments may exceed GitHub's 65 KB limit. | The gem does not paginate or truncate. The caller must filter by `entry.severity` before export. There is no `min_severity:` parameter on the exporters in v1 (the operator guide flags this as TODO). |
| **Cross-process trend amnesia** | `History::Store` is in-memory only. CI workers are typically ephemeral; trends reset every run. | Trend always reports `:stable` in stateless CI. | Operator must serialize `store.all` between runs (documented, not implemented in helper code). |
| **Eviction skew under pressure** | `enforce_limit!` evicts by `min_by(&:first_seen)`. Long-lived stable-then-flaky tests get evicted before newly-detected flakes. | Stale tests vanish; useful trend history lost. | Raise `max_history_entries`. The 10,000 default holds a large Rails suite, but a polyglot mono-CI ingesting many projects can hit it. |
| **Parser silent skip** | `extract_examples` swallows `ArgumentError` and drops entries (`parsers/rspec_json.rb:42`). A reporter regression that produces 100% malformed examples returns `[]` results, not a `ParseError`. | Empty input → empty report → no signal that anything is wrong. | Operator should verify `results.size > 0` before declaring "no flakes." |
| **REXML attack surface** | JUnit XML is parsed by Ruby stdlib REXML. REXML disables external entities by default in recent Rubies; older versions had XXE concerns. | Resource exhaustion on adversarial XML. | Decision 3 accepts REXML's tradeoffs explicitly. The adversarial spec tests large inputs (1000+ test cases in <5s) but does not test XML billion-laughs / entity expansion. |

The catastrophic-impact column for every row above is "engineer wastes time" or "report unreliable." There is no row that reads "data leaked," "infrastructure compromised," "production affected." That is the value of the Archetype C posture.

---

## 6. Trade-off Analysis

### 6.1 Pure library gem, no CLI / no MCP / no daemon

The gem ships as `require 'wild_test_flake_forensics'` and nothing else. No `bin/`, no MCP server, no HTTP API. Decision 1 in `004-AT-ADEC`.

**For:** zero operational burden, zero attack surface, zero dependency on a long-running process. The caller controls the schedule, the input source, the output destination. Every wild-ecosystem operator can wire this into their existing Rake/CI tooling without learning a new lifecycle.

**Against:** every adopter writes the same ~10 lines of glue. There is no `flake-forensics analyze ci_results/*.json` one-liner for the hallway test. The "Quick start" in the README assumes the reader is comfortable opening a Ruby REPL. A team without an existing Ruby gem habit (a JS shop with a single Rails admin, for example) has higher activation energy.

**Verdict:** correct for the v1 user — a Ruby/Rails team that already has a Rakefile. Wrong for v2's hypothetical adoption beyond Ruby shops; that adoption case would justify a thin wrapper repo, not changing this gem.

### 6.2 In-memory `History::Store`, no persistence

Decision 2. `History::Store` is a `Hash`, capped at `max_history_entries`, lost on process exit.

**For:** no schema migrations, no file locking, no SQLite/Redis dependency, no persistence-layer security model (file permissions, backup, restore, GDPR). The capped Hash is provably bounded — `enforce_limit!` runs after every insert. The model maps cleanly to a CI batch-job lifecycle ("read N runs, analyze, write report, exit").

**Against:** the trend feature is effectively unusable in a typical CI worker. Workers are ephemeral. `trend_for(identity)` returns `:stable` for every flake on first run. The gem documents this honestly ("If you want multi-session trend tracking, you must serialize and reload state yourself") but provides no helper to do so — no `Store#dump`/`Store#load`, no Marshal hook. The operator who wants trends must hand-roll an adapter behind `Store`.

**Verdict:** correct for v1 scope; the persistence layer is the single most-likely v2 addition. The current code is well-positioned for it because `Store` is the only stateful component and its interface is small.

### 6.3 Confidence-scored multi-hypothesis root causes vs single-label classification

Decision 4. Every flake carries an array of `RootCause` objects, each with `confidence ∈ [0, 1]`.

**For:** flakes legitimately have multiple causes. A test sensitive to both timing *and* shared state should surface both. The gem refuses to pick a winner when it lacks signal. Remediation pulls suggestions from the top-N causes (up to 6 unique), so multiple hypotheses still produce actionable output. `primary_root_cause` exists as a convenience for callers who insist on a single label (`max_by(&:confidence)`).

**Against:** the confidence numbers are not calibrated. `random_seed_signal` returns a literal `0.8` when failure-seeds and pass-seeds are disjoint. `timing_signal` returns `min(CV × 1.5, 1.0)` with no validation against ground-truth flake data. The numbers feel meaningful but are essentially heuristic dial readings. A reader may treat `confidence: 0.8` as "the model is 80% sure" when the correct reading is "the gem's hand-rolled signal-extractor produced 0.8." The remediation table is also a static lookup — `confidence: 0.9` for `:timing_dependent` returns the same four suggestions as `confidence: 0.2` for `:timing_dependent`. Confidence affects ranking, not advice.

**Verdict:** the multi-hypothesis structure is good. The confidence numbers need a calibration story before they can support automated decisions (auto-quarantine, auto-revert). Right now they are best read qualitatively (high/medium/low buckets exist on `RootCause`) and v2 would benefit from a calibration corpus.

---

## 7. Operator Playbook

### 7.1 Wire into CI

The minimum-effort path is a Rake task that runs in a post-suite step. Save as `lib/tasks/flake_report.rake`:

```ruby
task :flake_report do
  require 'wild_test_flake_forensics'
  results = Dir['ci_results/run-*.json'].each_with_index.flat_map do |path, i|
    WildTestFlakeForensics::Parsers::RspecJson.parse(File.read(path), run_id: "run-#{i+1}")
  end
  flakes   = WildTestFlakeForensics::Detection::FlakeDetector.new.detect(results)
  analyzed = WildTestFlakeForensics::Analysis::RootCauseAnalyzer.new
               .analyze(flakes, all_results: results)
  entries  = WildTestFlakeForensics::Triage::Engine.new.triage(analyzed)
  File.write('flake-report.md',
             WildTestFlakeForensics::Export::MarkdownExporter.new.export(entries))
  puts WildTestFlakeForensics::Export::SummaryExporter.new.export(entries)
end
```

Your CI workflow must download or persist the last N runs' RSpec JSON artifacts into `ci_results/`. The gem does not do this.

### 7.2 Inspect a flake report

`flake-report.md` lists tests sorted by `severity_score` descending. For each entry, read in this order: severity, flake rate, trend, top root cause, remediation bullets. If the top cause is `:external_dependency` with confidence > 0.5 and at least one of the matched error messages mentions a service you control, that is your first investigation lane. If the top cause is `:unknown`, run the suspect test in isolation first (per the `:unknown` remediation list).

### 7.3 Suppress a known flake

There is no built-in suppression mechanism. The gem reports everything it detects. To suppress, filter at the caller level before export:

```ruby
KNOWN_FLAKES = ['UserController loads user profile']
entries = entries.reject { |e| KNOWN_FLAKES.include?(e.test_identity.test_name) }
```

A `min_severity:` parameter on the exporters is listed in the operator guide as future work but is not in v1.

### 7.4 Recover after detector crash

The gem holds no persistent state. A crash inside `detect`, `analyze`, or `triage` loses only the current run's in-flight computation. Re-run the pipeline; no cleanup is required. If `Parsers::*#parse` raises `ParseError`, the caller will see it. If it returns `[]` despite a non-empty input file, suspect a reporter regression (silent skip described in §5) and inspect the input manually. The `Configuration` object cannot be re-mutated after `configure {}` completes — if you need a different threshold mid-process, call `WildTestFlakeForensics.reset_configuration!` then `configure` again (intended for tests only).

---

## 8. Recommendations for v2

The v1 scope was correct. The following gaps will start to bite when this gem is wired into more than one team's CI:

1. **Ship a `bin/flake-forensics` or an explicit CI helper gem.** The 10-line glue contract is friction; one teammate writing it slightly wrong (wrong glob, wrong run_id sequencing) breaks detection silently. A `bin/` wrapper or a sibling gem with a GitHub Action would close the activation-energy gap without violating Decision 1's spirit (the library would remain pure).
2. **Add `History::Store#dump` / `Store.load` for cross-process persistence.** The trend feature is currently theoretical in CI. A `Marshal`-based serializer or a `to_h` round-trip would make it real. Keep it as an opt-in adapter so Decision 2 holds for stateless callers.
3. **Add a `min_severity:` filter to the exporters.** Already promised in `006-OD-GUID`'s TODO list. Cheap, immediate operator value, no architectural risk.
4. **Calibrate the confidence numbers** against a labeled corpus, or stop using floats and switch to ordinal buckets (`:high`/`:medium`/`:low`) in the public API. The current numbers invite a precision they do not have.
5. **Tighten `random_seed_signal`'s 0.8 hard-coded jump.** Two-or-three data points should not yield 0.8 confidence. Scale by sample size or apply a Beta-prior smoothing.
6. **Test for adversarial XML.** Add specs for billion-laughs and entity-expansion against `JunitXml#parse`. REXML's defaults are sane in modern Ruby, but the safety model would be stronger with explicit coverage.
7. **Dogfood it.** The gem's own CI does not run it against its own RSpec output. Adding a job that does — even as `continue-on-error` — would catch reporter-regression silent-skip and would give the team a reflexive smoke test.
8. **Wire it into the other nine wild repos.** Currently zero do (see Brief Report). At minimum, the four Ruby/Rails repos in the ecosystem should depend on it as a dev-dependency and add a CI step.

---

**Length:** ~3,100 words.
**Cross-references:** `000-docs/001-PP-PLAN-repo-blueprint.md`, `000-docs/003-TQ-STND-safety-model.md`, `000-docs/004-AT-ADEC-architecture-decisions.md`, `000-docs/005-DR-REFF-configuration-reference.md`, `000-docs/006-OD-GUID-operator-workflow-guide.md`.

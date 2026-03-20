# 001-PP-PLAN — Repo Blueprint: wild-test-flake-forensics

**Filing code:** PP-PLAN
**Status:** v1
**Archetype:** C — SDLC Companion

---

## Mission

Detect flaky tests from CI history, correlate flake signals to likely root causes with confidence scores, and produce structured triage artifacts that help engineering teams prioritize and fix test instability.

This library makes it possible to answer "which tests are flaky, why, and which ones matter most?" — without requiring any changes to how CI is run or test suites are structured.

---

## Problem statement

Flaky tests are one of the most corrosive forces in a CI pipeline. A test that sometimes fails without a code change burns developer time, erodes trust in the test suite, and introduces false signal into CI feedback loops. Most teams deal with flakes reactively: someone notices a test failing intermittently, quarantines it, and eventually forgets about it.

What teams need is structured forensics: the ability to ingest runs from existing CI output, identify patterns of instability across runs, hypothesize likely root causes from observable signals, and produce a triage-ready report sorted by severity and actionability.

This gem is that tool.

---

## Boundaries

**In scope:**

- Parsing CI test output (RSpec JSON, JUnit XML, minitest JSON)
- Detecting tests that exhibit both pass and fail outcomes across multiple runs
- Producing confidence-scored root cause hypotheses from observable signals
- Scoring and ranking flaky tests by severity
- Suggesting remediation strategies per root cause category
- Tracking flake history and computing trends (worsening / stable / improving)
- Exporting results in JSON, Markdown, and plain-text summary formats

**Out of scope:**

- Executing tests or CI pipelines
- Automatically fixing flaky tests
- Storing state to disk or a database
- Monitoring production systems or runtime behavior
- Collecting telemetry or reporting to external services
- Replacing CI/CD tools (GitHub Actions, CircleCI, Buildkite, etc.)
- Network I/O of any kind

---

## Non-goals

1. This is not a test runner. It never invokes any test command.
2. This is not a database. History is in-memory only, bounded by configuration.
3. This is not a CI plugin or GitHub Action. It is a Ruby library that calling code integrates.
4. This is not a classifier that produces binary "flaky / not flaky" labels. It produces confidence-scored hypotheses.
5. This is not a monitoring agent. It processes data you hand it; it does not collect data on its own.

---

## Archetype declaration

This is an **Archetype C — SDLC Companion** repo. It operates entirely within the software development lifecycle, on developer machines or in CI scripts. It has no production runtime footprint, no network surface, and no persistent storage. Its safety posture is accordingly light: input validation, bounded memory, safe handling of path-like strings, and no command execution.

---

## Users

**Primary:** Engineering teams and platform teams in organizations where flaky tests are a known drag on productivity. The library is used by whoever owns CI health — often a platform engineer, a senior developer, or a test reliability initiative.

**Secondary:** Individual developers debugging a specific intermittently-failing test who want structured analysis rather than manual log reading.

**Integration mode:** Typically called from a CI script or a Rake task after accumulating test results from multiple runs. Results are piped to a report file, a Slack message, or a dashboard.

---

## Use cases

**UC-01: Detect and triage across a week of CI runs**
A platform engineer exports RSpec JSON from the last 5 days of CI runs. They load all results into the detector, run analysis, triage, and export a Markdown report pinned to their internal wiki. The report shows 3 critical flakes, 7 high flakes, with root cause hypotheses and per-flake remediation suggestions.

**UC-02: Gate a flaky test before merging**
A CI script parses the last 20 runs for a specific test file. If any test is detected as flaky with severity >= high, the script prints a summary report and exits non-zero. The developer sees which test is flaky and the suggested fix before merge.

**UC-03: Trend tracking over a release cycle**
A Rake task loads parsed results into a History::Store across multiple CI runs throughout a sprint. At the end of the sprint, a trend report identifies which flakes are worsening and need immediate action before the release.

**UC-04: Debugging a specific intermittent failure**
A developer adds verbose logging to a known intermittent test. They run it 10 times manually, parse the results through MinitestJson, and call analyze to get the confidence-scored root cause breakdown. The analyzer returns high confidence for `external_dependency`, suggesting the test is hitting a real service.

---

## Architecture direction

The gem is a pure Ruby library with no runtime dependencies beyond stdlib. It follows a pipeline architecture: parse raw format input into normalized `TestResult` objects, detect flake patterns by grouping across runs, analyze signals to score root causes, triage to produce severity-ranked entries, and export to the desired format.

Each stage is independently instantiable and testable. There is no global singleton orchestrator — calling code assembles the pipeline. Configuration is module-level, validated at assignment time, and frozen after the `configure` block completes.

Persistence is intentionally out of scope for v1. The History::Store is an in-memory accumulator with a configurable size cap and LRU-style eviction.

See `004-AT-ADEC-architecture-decisions.md` for the rationale behind each major design decision.

---

## Ecosystem position

`wild-test-flake-forensics` is a standalone utility gem. It has no dependencies on other wild repos and no dependents in v1. Future integration points include:

- `wild-session-telemetry` — session telemetry could record which flake patterns are seen across sessions
- `wild-gap-miner` — gap analysis could flag test suites with high flake rates as a signal
- `wild-transcript-pipeline` — transcripts from pairing sessions mentioning flaky tests could feed into gap identification

These integrations are speculative and not planned for v1.

# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

## Identity

- **Repo:** wild-test-flake-forensics
- **Ecosystem:** wild (see `../CLAUDE.md` for ecosystem-level rules)
- **Archetype:** C — SDLC Companion
- **Mission:** Detect flaky tests, analyze root causes, and support triage
- **Namespace:** WildTestFlakeForensics
- **Language:** Ruby 3.2+, pure library gem (no MCP, no ActiveRecord)
- **Status:** v1 complete — all 10 epics implemented, 277 tests passing, 0 RuboCop offenses

## What This Repo Does

- Parses CI test output in three formats: RSpec JSON, JUnit XML, minitest JSON
- Detects flaky tests by grouping results across runs and applying configurable thresholds
- Produces confidence-scored root cause hypotheses (timing, shared state, external deps, random seed, resource contention, timezone/locale)
- Scores and ranks flaky tests by severity (critical / high / medium / low) with configurable weights
- Exports triage reports to JSON, Markdown, and plain-text summary formats
- Tracks flake history in-memory and computes worsening/stable/improving trends

## What This Repo Does NOT Do

- Execute tests or invoke CI commands
- Persist state to disk or a database
- Communicate over a network (no HTTP, no sockets)
- Fix flaky tests automatically
- Operate as an MCP server or HTTP service

## Directory Layout

```
wild-test-flake-forensics/
  000-docs/               canonical documentation
  lib/
    wild_test_flake_forensics.rb          entry point, configure interface
    wild_test_flake_forensics/
      configuration.rb                   validated, freeze-on-configure config
      errors.rb                          error hierarchy
      version.rb                         VERSION = '0.1.0'
      models/                            TestIdentity, TestResult, RootCause,
                                         FlakeRecord, TriageEntry
      parsers/                           Base, RspecJson, JunitXml, MinitestJson
      detection/                         Comparator, FlakeDetector
      analysis/                          SignalExtractors (mixin), RootCauseAnalyzer
      triage/                            SeverityScorer, Remediation, Engine
      history/                           Store, TrendAnalyzer
      export/                            JsonExporter, MarkdownExporter, SummaryExporter
  spec/
    spec_helper.rb
    support/fixtures.rb                  shared test fixtures and helpers
    wild_test_flake_forensics/           unit specs (mirrors lib/ structure)
    integration/                         full_pipeline_spec, multi_format_spec
    adversarial/                         malformed_input_spec, edge_cases_spec
  planning/               pre-implementation notes (superseded by 000-docs)
  Gemfile
  Rakefile
  wild-test-flake-forensics.gemspec
```

## Build Commands

```bash
bundle install
bundle exec rspec                    # run all 277 specs
bundle exec rspec spec/unit/...      # run a specific spec file
bundle exec rubocop                  # lint (must be 0 offenses)
bundle exec rake                     # default: runs rspec
```

## Safety Rules for Claude Code

1. Never add code that executes shell commands, spawns subprocesses, or invokes test runners.
2. Never add code that reads filesystem paths derived from TestIdentity.file_path — that field is metadata for display only.
3. Validate all parser input before processing; raise ParseError on structurally invalid input, skip (not raise) on invalid individual entries.
4. Keep History::Store bounded; do not remove or bypass the max_entries enforcement.
5. Do not add network I/O, HTTP clients, or socket operations to this library.
6. Do not add runtime gem dependencies; this gem has zero runtime dependencies by design.
7. Do not mutate configuration after freeze; use reset_configuration! in tests only.

## Key Canonical Docs

| Doc | Purpose |
|-----|---------|
| 000-docs/001-PP-PLAN-repo-blueprint.md | Mission, boundaries, users, use cases |
| 000-docs/002-PP-PLAN-epic-build-plan.md | 10-epic build narrative |
| 000-docs/003-TQ-STND-safety-model.md | Safety rules and rationale |
| 000-docs/004-AT-ADEC-architecture-decisions.md | Why things are shaped the way they are |
| 000-docs/005-DR-REFF-configuration-reference.md | All config parameters with types and defaults |
| 000-docs/006-OD-GUID-operator-workflow-guide.md | Usage flow, config examples, report reading |

## Task Tracking

Beads is the task tracker for this ecosystem. Tasks for this repo are tracked under the `wild` ecosystem beads instance. Run `bd list` to see current tasks. The Phase 0 doc pack is the current active work unit.

## Before Working Here

1. Read `../CLAUDE.md` for ecosystem-level rules and work sequence standards.
2. Read `000-docs/001-PP-PLAN-repo-blueprint.md` for mission and boundaries.
3. Read `000-docs/004-AT-ADEC-architecture-decisions.md` before changing any structural decisions.
4. Run `bundle exec rspec` and confirm 277 examples, 0 failures before making changes.
5. Run `bundle exec rubocop` and confirm 0 offenses before committing.
6. Safety rule 1 is non-negotiable: never add test execution or subprocess invocation.

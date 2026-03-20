# wild-test-flake-forensics

Detect flaky tests from CI history, score root causes by confidence, and produce prioritized triage reports.

## What it does

- Parses CI test output from RSpec JSON, JUnit XML, and minitest JSON formats
- Detects tests that flip between pass and fail across multiple CI runs
- Analyzes root cause hypotheses with confidence scores: timing dependency, shared state, external dependencies, random seed variance, resource contention, timezone/locale issues
- Scores and ranks flaky tests by severity (critical / high / medium / low) with configurable weighting
- Tracks flake history and detects worsening, stable, or improving trends
- Exports reports to JSON, Markdown, and CI-friendly plain-text summary

## What it does NOT do

- Execute tests or manage CI pipelines
- Fix flaky tests automatically
- Persist state to disk or a database
- Communicate over any network
- Replace CI/CD tools

## Quick start

```ruby
require 'wild_test_flake_forensics'

# Parse results from multiple CI runs
all_results = Dir['ci_results/run-*.json'].each_with_index.flat_map do |path, i|
  WildTestFlakeForensics::Parsers::RspecJson.parse(File.read(path), run_id: "run-#{i + 1}")
end

# Detect flaky tests
flakes = WildTestFlakeForensics::Detection::FlakeDetector.new.detect(all_results)

# Analyze root causes
analyzed = WildTestFlakeForensics::Analysis::RootCauseAnalyzer.new.analyze(flakes, all_results: all_results)

# Triage and prioritize
entries = WildTestFlakeForensics::Triage::Engine.new.triage(analyzed)

# Export
puts WildTestFlakeForensics::Export::SummaryExporter.new.export(entries)
File.write('flake-report.md', WildTestFlakeForensics::Export::MarkdownExporter.new.export(entries))
File.write('flake-report.json', WildTestFlakeForensics::Export::JsonExporter.new.export(entries))
```

## Configuration

```ruby
WildTestFlakeForensics.configure do |config|
  config.minimum_runs         = 5      # Minimum runs before detection (default: 3)
  config.flake_rate_threshold = 0.15   # Minimum flip rate to qualify (default: 0.1)
  config.max_history_entries  = 5_000  # History store size limit (default: 10_000)
  config.severity_weights     = {      # Score formula weights (default: all 1.0)
    flake_rate:    2.0,
    failure_count: 1.0,
    trend:         1.0,
    confidence:    1.5
  }
end
```

Configuration is frozen after the configure block. Use `WildTestFlakeForensics.reset_configuration!` in tests to restore defaults.

## Supported input formats

- **RSpec JSON** — `rspec --format json`
- **JUnit XML** — standard `<testsuite>` / `<testsuites>` format from any CI system
- **minitest JSON** — minitest-reporters or compatible, with `tests` or `results` root key

## Running tests

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

Expected output:

```
277 examples, 0 failures
55 files inspected, no offenses detected
```

## Status

v1 complete — 277 tests, 0 RuboCop offenses

All 10 epics implemented: scaffold, configuration, models, parsers, detection, root cause analysis, triage, history/trends, export, adversarial hardening.

## Documentation

See `000-docs/` for the full canonical doc pack:

- `001-PP-PLAN-repo-blueprint.md` — mission, boundaries, users, use cases
- `002-PP-PLAN-epic-build-plan.md` — 10-epic build narrative
- `003-TQ-STND-safety-model.md` — Archetype C safety rules
- `004-AT-ADEC-architecture-decisions.md` — key design decisions with rationale
- `005-DR-REFF-configuration-reference.md` — all configuration parameters
- `006-OD-GUID-operator-workflow-guide.md` — workflow guide and integration examples

## Part of the Wild ecosystem

`wild-test-flake-forensics` is a standalone utility library in the [wild](../CLAUDE.md) ecosystem — a family of SDLC tooling repos built for engineering teams. It has no dependencies on other wild repos and can be used independently.

## License

Intent Solutions Proprietary. See LICENSE.

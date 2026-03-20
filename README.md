# wild-test-flake-forensics

Detects flaky tests from CI history, correlates flake signals to likely root causes, and produces structured triage artifacts for engineering teams.

Part of the **wild** ecosystem. See `../CLAUDE.md` for ecosystem-level guidance.

## What it does

- Parses CI test results (RSpec JSON, JUnit XML, minitest JSON)
- Detects flaky tests across runs (tests that flip between pass/fail without code changes)
- Analyzes root cause hypotheses with confidence scores: timing, ordering, shared state, external deps, random seeds, resource contention, timezone/locale
- Produces prioritized triage reports with severity scoring and remediation suggestions
- Tracks flake history and detects improving/worsening/stable trends
- Exports to JSON, Markdown, and summary (CI-friendly) formats

## What it does NOT do

- Execute tests or manage CI pipelines
- Fix flaky tests automatically
- Replace CI/CD tools
- Monitor production systems
- Collect telemetry

## Installation

Add to your Gemfile:

```ruby
gem 'wild-test-flake-forensics'
```

## Usage

```ruby
require 'wild_test_flake_forensics'

# Parse test results from multiple CI runs
run1 = WildTestFlakeForensics::Parsers::RspecJson.parse(
  File.read('results/run1.json'), run_id: 'run-001'
)
run2 = WildTestFlakeForensics::Parsers::RspecJson.parse(
  File.read('results/run2.json'), run_id: 'run-002'
)

# Detect flaky tests
detector = WildTestFlakeForensics::Detection::FlakeDetector.new
flakes = detector.detect(run1 + run2)

# Analyze root causes
analyzer = WildTestFlakeForensics::Analysis::RootCauseAnalyzer.new
analyzed = analyzer.analyze(flakes, all_results: run1 + run2)

# Triage and prioritize
engine = WildTestFlakeForensics::Triage::Engine.new
entries = engine.triage(analyzed)

# Export
puts WildTestFlakeForensics::Export::SummaryExporter.new.export(entries)
puts WildTestFlakeForensics::Export::MarkdownExporter.new.export(entries)
```

## Configuration

```ruby
WildTestFlakeForensics.configure do |config|
  config.minimum_runs = 5               # Minimum runs before detection (default: 3)
  config.flake_rate_threshold = 0.15    # Minimum flip rate to qualify (default: 0.1)
  config.max_history_entries = 5_000    # History store size limit (default: 10_000)
end
```

## Supported formats

- RSpec JSON (`--format json`)
- JUnit XML (all major CI systems)
- Minitest JSON (minitest-reporters or similar)

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

Nonstandard. See LICENSE.

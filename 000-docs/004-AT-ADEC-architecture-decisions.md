# 004-AT-ADEC — Architecture Decisions: wild-test-flake-forensics

**Filing code:** AT-ADEC
**Status:** v1

---

## Decision 1: Pure library gem, no MCP server

**Decision:** Ship as a plain Ruby library gem (`require 'wild_test_flake_forensics'`). No MCP server, no HTTP server, no CLI binary, no daemon.

**Rationale:**
- The primary integration point for test forensics is a Rake task or CI script, not an LLM session or a running service.
- A library gem has the lowest possible operational burden: no ports, no processes, no configuration files, no deployment.
- MCP integration can be layered on top by a thin wrapper gem if needed in a future iteration. The library API is clean enough to wrap.
- Adding an MCP server would require network hardening, authentication, and a more complex safety model — none of which are needed for the core use case.

**Consequences:**
- Callers must write glue code (a few lines of Ruby) to integrate. There is no out-of-the-box CLI.
- This is intentional: the library is composable, not opinionated about how it's invoked.

**Alternatives considered:** MCP server (rejected: operational overhead without near-term benefit), standalone CLI binary (rejected: harder to compose, adds optparser dependency).

---

## Decision 2: In-memory storage for v1, no persistence layer

**Decision:** The History::Store is a pure in-memory hash. No database, no file persistence, no Redis, no SQLite.

**Rationale:**
- The primary use case is stateless: parse a batch of CI run outputs, analyze, export a report. Persistence is not needed for this.
- Persistence adds complexity (schema migration, file locking, connection pooling) that is not justified by v1 requirements.
- The max_history_entries cap (default 10,000) ensures memory stays bounded even in long-running integration scenarios.
- If persistence becomes necessary (e.g., for trend tracking over weeks), it can be added as an adapter behind the Store interface without changing callers.

**Consequences:**
- Trend data does not survive process restarts. If you want multi-session trend tracking, you must serialize and reload FlakeRecord state yourself.
- This is a documented limitation, not a defect.

**Alternatives considered:** SQLite via sequel (rejected: adds dependency, migration complexity), Marshal/YAML serialization to file (rejected: creates implicit filesystem coupling, security surface).

---

## Decision 3: REXML for XML parsing (stdlib, no external deps)

**Decision:** Use `rexml` from Ruby's standard library to parse JUnit XML. Do not add Nokogiri, ox, or other third-party XML parsers.

**Rationale:**
- REXML is bundled with Ruby and is sufficient for well-formed JUnit XML, which is a simple, shallow document structure.
- Nokogiri requires native extensions and has a larger installation footprint. For a library gem used in CI environments, minimizing native extension dependencies is a significant advantage.
- JUnit XML is a small, well-specified format. REXML's XPath support (`REXML::XPath.each(doc, '//testcase')`) handles it cleanly.
- The gemspec has no runtime dependencies. This is an explicit design goal.

**Consequences:**
- REXML is slower than Nokogiri for large documents. For JUnit XML from a single CI run (typically hundreds to low thousands of test cases), this is not a meaningful concern.
- REXML is listed in the Gemfile as `gem 'rexml', '>= 3.2'` because it was extracted from Ruby's default gems in Ruby 3.0 and must be explicitly required in some bundler configurations.

**Alternatives considered:** Nokogiri (rejected: native extensions, larger footprint), ox (rejected: not in stdlib, less widely known), hand-rolled regex parsing (rejected: fragile).

---

## Decision 4: Confidence-scored root causes, not binary classification

**Decision:** Root cause analysis produces an array of `RootCause` objects, each with a `confidence` score in [0.0, 1.0], rather than a single classification label.

**Rationale:**
- Flaky tests frequently have multiple contributing causes. A test that fails intermittently due to both timing sensitivity and shared state should surface both hypotheses.
- Binary classification ("this test is order-dependent") is overconfident. The signals available from CI output (error messages, duration variance, metadata, co-occurrence patterns) are indirect. Expressing uncertainty explicitly is more honest and more useful.
- Confidence thresholds (high >= 0.7, medium >= 0.4, low < 0.4) let callers decide how much certainty they require before acting.
- The CONFIDENCE_THRESHOLD filter (0.15) prevents low-signal noise from cluttering results without forcing a single winner.

**Consequences:**
- Callers get richer information but must handle an array of hypotheses rather than a single answer.
- The `primary_root_cause` method on FlakeRecord returns `root_causes.max_by(&:confidence)` as a convenience for callers who need a single label.
- Remediation suggestions are generated from the top-N root causes (up to 6 unique suggestions), so multiple hypotheses still produce actionable output.

**Alternatives considered:** Single-label classification (rejected: overconfident, loses information), probability distribution over all categories (rejected: unnecessary precision, harder to communicate).

---

## Decision 5: Normalized TestResult model, parser-agnostic pipeline

**Decision:** All parsers normalize their output to `Models::TestResult` objects before any downstream processing. No component downstream of the parser layer knows or cares which format the data came from.

**Rationale:**
- Three input formats (RSpec JSON, JUnit XML, minitest JSON) need to flow through the same detection, analysis, triage, and export pipeline. A shared model makes this possible without conditional branching in every downstream component.
- The normalized model captures the minimum viable fields needed by all downstream components: test identity (file, name, context), status, run_id, timestamp, duration_ms, error_message, metadata.
- Format-specific quirks (RSpec's `exception.message`, JUnit's `classname`-to-file mapping, minitest's `result`/`status` field naming) are handled entirely within the parser.
- Adding a fourth parser format (e.g., pytest JSON, TAP) requires only implementing `Parsers::Base`, not touching any other component.

**Consequences:**
- Some format-specific information is discarded during normalization (e.g., RSpec example IDs, JUnit suite names). If this information is needed later, a metadata hash field is available on TestResult for parser-specific extras.

**Alternatives considered:** Format-specific models passed to format-aware detection (rejected: couples detection and analysis to format knowledge), raw hash passing (rejected: no type safety, no validation).

---

## Decision 6: Configurable severity weights

**Decision:** The four inputs to the severity score formula (flake_rate, failure_count, trend, confidence) are configurable via `severity_weights` in Configuration, defaulting to equal weights (1.0 each).

**Rationale:**
- Different teams have different priorities. A team that runs 50 CI runs per day cares more about failure_count. A team with a flaky production-linked integration suite may weight confidence more heavily.
- Making weights configurable without requiring a subclass or monkey-patch is a clean extension point.
- Equal default weights produce sensible out-of-the-box severity rankings without requiring any configuration.
- The `VALID_SEVERITY_WEIGHT_KEYS` constant prevents typos and unknown keys from silently producing wrong scores.

**Consequences:**
- The score formula is a simple weighted average, not a trained model. It can produce unexpected rankings if weights are set to extreme values. This is documented as operator responsibility.
- Weight validation happens at assignment time (ConfigurationError), not at score calculation time.

**Alternatives considered:** Fixed weights (rejected: too opinionated, limits adaptability), subclass-based strategy pattern (rejected: too complex for what is essentially four numbers).

---

## Decision 7: Immutable configuration after startup

**Decision:** After the `WildTestFlakeForensics.configure` block completes, the configuration object is frozen. Subsequent mutation attempts raise `FrozenError`.

**Rationale:**
- Configuration that can change at any point during a program's execution introduces race conditions and unexpected behavior in multi-threaded contexts.
- Freezing configuration at startup makes it safe to read from multiple threads without locks.
- It also makes bugs visible early: a component that accidentally mutates configuration will fail immediately with a clear error, not silently change behavior elsewhere.
- The `reset_configuration!` class method exists for testing, where each test gets a clean configuration.

**Consequences:**
- Configuration cannot be changed after the first `configure` block. This is intentional and desirable.
- Tests must call `WildTestFlakeForensics.reset_configuration!` in a before hook to get a clean slate. The spec_helper does this automatically.

**Alternatives considered:** Mutable configuration throughout (rejected: thread-unsafe, hard to reason about), immutable value object (rejected: more complex, no advantage over freeze).

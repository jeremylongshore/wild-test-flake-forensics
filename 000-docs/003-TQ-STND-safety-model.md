# 003-TQ-STND — Safety Model: wild-test-flake-forensics

**Filing code:** TQ-STND
**Status:** v1
**Archetype:** C — SDLC Companion (light safety posture)

---

## Archetype C safety posture

Archetype C repos are SDLC companions: they operate on developer machines and in CI scripts, processing data that engineers hand them. They have no production runtime footprint, no network surface, no persistent storage, and no command execution surface.

The threat profile for an SDLC companion is correspondingly narrow:
- Malformed or adversarially crafted input data causing crashes or unbounded resource usage
- File path strings from test output being treated as actual filesystem paths
- Memory growth without bound in long-running processes
- Sensitive deployment information leaking into exported reports

No authentication, authorization, secrets handling, or network hardening is required. No audit logging of user actions is required. No data classification scheme is required.

---

## Safety rules

### Rule 1: Never execute tests or CI commands

The library must never invoke shell commands, spawn subprocesses, or execute test runners. It processes data it is given; it does not collect data on its own.

**Implementation:** The library has zero subprocess or shell execution surface. There are no calls to `system`, `exec`, backtick operators, `Open3`, `Kernel.spawn`, `IO.popen`, or equivalent. This rule applies to all current and future code.

**Verification:** Running `grep -r "system\|`\|exec\|spawn\|Open3\|popen" lib/` should produce no results.

---

### Rule 2: Validate all parser input before processing

Parsers must validate that input is non-empty and structurally valid before attempting to extract data. Invalid structural input must raise `ParseError` with a descriptive message. Invalid individual entries within an otherwise valid document must be skipped, not raised.

**Implementation:**
- `Parsers::Base#require_non_empty!` rejects nil, empty string, and whitespace-only input.
- Each parser validates root structure before processing (e.g., RspecJson requires an "examples" key; JunitXml requires a `<testsuite>` or `<testsuites>` root; MinitestJson requires a "tests" or "results" key).
- Individual example/test case entries that fail to build a valid TestResult are rescued and skipped.
- REXML::ParseException and JSON::ParserError are caught and re-raised as ParseError.

**Rationale:** Callers should get a clear error if they pass in the wrong file or a truncated document. They should still get partial results from a document with a few malformed entries.

---

### Rule 3: Bound history storage growth

The History::Store must never grow without bound. The `max_history_entries` configuration parameter caps the number of FlakeRecord objects stored. When the cap is exceeded, the oldest record is evicted.

**Implementation:**
- `History::Store#enforce_limit!` is called after every `record` operation.
- Eviction uses `min_by { |_, r| r.first_seen }` to remove the oldest record.
- The per-key snapshot ring buffer is capped at 50 entries per test.
- `max_history_entries` defaults to 10,000 and must be a positive integer.

**Rationale:** In a long-running CI integration process, accumulating results indefinitely would cause unbounded memory growth. Bounded storage is a hard requirement for embedded use.

---

### Rule 4: Strip file paths that could leak deployment information in exports

Exported reports should not contain absolute server filesystem paths or deployment-revealing directory structures. When exporting, file_path values that are relative (starting with `./`, `spec/`, `test/`) are safe to include as-is. Absolute paths should be considered sensitive.

**Current status:** v1 exports file_path as provided by the parser, which reflects what CI tools report. RSpec JSON typically reports relative paths (`./spec/models/user_spec.rb`). JUnit XML uses classname-derived paths (`User/validates_email.rb`). Minitest JSON uses the `file` field if present.

**Operator guidance:** If your CI output contains absolute paths with server hostnames, working directories, or other deployment-revealing information, sanitize file_path values before calling the exporter, or post-process the JSON output. A future version may add a configurable path normalizer.

**Rule for Claude Code:** Do not add features that read from or write to actual filesystem paths based on the test file_path field. That field is metadata for display only.

---

### Rule 5: Reject path traversal attempts in test file references

The library stores and displays file_path strings from test output but must never attempt to read, write, or resolve those paths as actual filesystem paths. A file_path value of `../../../etc/passwd` must be stored and displayed as-is without any filesystem operation.

**Implementation:**
- TestIdentity stores file_path as a frozen string with no normalization.
- No code in the library reads files using file_path values.
- The adversarial test suite explicitly verifies that path-traversal-style file_path values pass through without error and without filesystem access.

**Rationale:** CI test output can contain paths that look dangerous. The library is a data processor, not a filesystem tool. The path is metadata.

---

## What this model does NOT cover

- Authentication or authorization (no access control surface)
- Secrets or credentials (library handles no credentials)
- Network security (no network I/O)
- Audit logging (SDLC tool; no audit requirement)
- Data retention policies (in-memory only; process exit clears all state)
- Supply chain security (standard gem conventions apply)

---

## Review cadence

This safety model should be reviewed when:
- A new data source is added (new parser format)
- Export destinations change (e.g., HTTP export endpoint is added)
- Persistence is added (database or file-backed store)
- The library is promoted to a server-side or production-adjacent context

Any of the above would likely trigger an archetype reclassification to B or A.

# 005-DR-REFF — Configuration Reference: wild-test-flake-forensics

**Filing code:** DR-REFF
**Status:** v1

---

## Overview

Configuration is set via the `WildTestFlakeForensics.configure` block. After the block completes, the configuration object is frozen and cannot be modified. Attempting to set any parameter on a frozen configuration raises `FrozenError`.

```ruby
WildTestFlakeForensics.configure do |config|
  config.minimum_runs = 5
  config.flake_rate_threshold = 0.15
  config.max_history_entries = 5_000
  config.severity_weights = { flake_rate: 2.0, failure_count: 1.0, trend: 0.5, confidence: 1.5 }
end
```

All parameters are optional. Calling `configure` with an empty block or not calling it at all uses the defaults described below.

To reset configuration (primarily for testing), call `WildTestFlakeForensics.reset_configuration!`. This creates a new unfrozen Configuration with all defaults restored.

---

## Parameters

### minimum_runs

| Attribute | Value |
|-----------|-------|
| Type | Integer |
| Default | `3` |
| Range | >= 1 |
| Error on invalid | `ConfigurationError: minimum_runs must be a positive integer` |

**Description:** The minimum number of runs a test must appear in before it is eligible for flake detection. Tests with fewer than `minimum_runs` observations are excluded from detection regardless of their pass/fail pattern.

**Guidance:** Lower values (2-3) detect flakes quickly but can produce false positives from statistical noise in sparse data. Higher values (5-10) require more history but produce more reliable detections. For CI pipelines that run multiple times per day, the default of 3 is reasonable. For less frequent pipelines, consider raising to 5.

**Component that reads this:** `Detection::FlakeDetector` (reads from config at initialization, can be overridden via constructor argument).

---

### flake_rate_threshold

| Attribute | Value |
|-----------|-------|
| Type | Float |
| Default | `0.1` |
| Range | 0.0 to 1.0 inclusive |
| Error on invalid | `ConfigurationError: flake_rate_threshold must be between 0.0 and 1.0` |

**Description:** The minimum proportion of runs that must be failures for a test to qualify as flaky. A value of `0.1` means at least 10% of observed runs must be failures. Tests with a failure rate below this threshold are not considered flaky.

**Guidance:** The default of 0.1 (10%) is appropriate for most teams. A test that fails once in ten runs is worth investigating. If you want to catch very rarely flaking tests (e.g., once in 50 runs), lower to 0.02. If you want to focus only on serious flakes, raise to 0.2 or 0.3.

**Formula:** `failure_count / total_runs >= flake_rate_threshold`

**Component that reads this:** `Detection::FlakeDetector` (reads from config at initialization, can be overridden via constructor argument).

---

### max_history_entries

| Attribute | Value |
|-----------|-------|
| Type | Integer |
| Default | `10_000` |
| Range | >= 1 |
| Error on invalid | `ConfigurationError: max_history_entries must be a positive integer` |

**Description:** The maximum number of `FlakeRecord` objects the `History::Store` will retain. When this limit is exceeded, the oldest record (by `first_seen` timestamp) is evicted to make room.

**Guidance:** The default of 10,000 is sufficient for very large test suites in long-running processes. Lower this value if you are operating in a memory-constrained environment. Note that this controls the number of distinct tests tracked, not the number of individual test results per test.

**Memory estimate:** Each FlakeRecord is lightweight (a few hundred bytes plus results array). At 10,000 entries with an average of 10 results each, expect roughly 10-50 MB depending on error message length.

**Component that reads this:** `History::Store` (reads from config at initialization, can be overridden via constructor argument).

---

### severity_weights

| Attribute | Value |
|-----------|-------|
| Type | Hash |
| Default | `{ flake_rate: 1.0, failure_count: 1.0, trend: 1.0, confidence: 1.0 }` |
| Valid keys | `:flake_rate`, `:failure_count`, `:trend`, `:confidence` |
| Value type | Numeric (Float or Integer) |
| Error on invalid | `ConfigurationError: severity_weights must be a Hash` or `ConfigurationError: severity_weights has invalid keys` |

**Description:** Weights applied to the four components of the severity score formula. Higher weight on a component means that component has more influence on the final score. Partial updates are merged with the defaults (you do not need to specify all four keys).

**Components and their meaning:**

| Key | What it measures | Notes |
|-----|-----------------|-------|
| `:flake_rate` | Raw proportion of failures (0.0 to 1.0) | Linear. A 50% flake rate contributes 0.5 * weight. |
| `:failure_count` | Volume of failures (log-scaled) | `log10(max(count, 1)) / 3.0`, capped at 1.0. At 10 failures this is ~0.33; at 1000 failures this is 1.0. |
| `:trend` | Direction of change | Uses TREND_MULTIPLIERS: worsening=0.9, stable=0.5, improving=0.1. |
| `:confidence` | Top root cause confidence | The highest confidence value among the flake's root causes. |

**Score formula:**

```
raw_score = (flake_rate * w_flake_rate
           + failure_count_score * w_failure_count
           + trend_multiplier * w_trend
           + top_confidence * w_confidence) / total_weight

final_score = [raw_score, 1.0].min
```

**Severity thresholds from score:**

| Score range | Severity |
|-------------|----------|
| >= 0.75 | `:critical` |
| 0.5 to < 0.75 | `:high` |
| 0.25 to < 0.5 | `:medium` |
| < 0.25 | `:low` |

**Example: emphasize flake rate and failure volume**

```ruby
WildTestFlakeForensics.configure do |config|
  config.severity_weights = { flake_rate: 3.0, failure_count: 2.0 }
  # trend and confidence retain their 1.0 defaults
end
```

**Component that reads this:** `Triage::SeverityScorer` (reads from config at initialization, can be overridden via constructor argument).

---

## Full defaults reference

```ruby
# These are the defaults. You only need to specify what you want to change.
WildTestFlakeForensics.configure do |config|
  config.minimum_runs         = 3
  config.flake_rate_threshold = 0.1
  config.max_history_entries  = 10_000
  config.severity_weights     = {
    flake_rate:     1.0,
    failure_count:  1.0,
    trend:          1.0,
    confidence:     1.0
  }
end
```

---

## Notes on constructor overrides

`FlakeDetector`, `SeverityScorer`, and `History::Store` all accept constructor-level overrides for their respective configuration parameters. This allows isolated instances with different settings without changing global configuration:

```ruby
# Global config: minimum_runs = 3
# This instance uses minimum_runs = 10, overriding global config
detector = WildTestFlakeForensics::Detection::FlakeDetector.new(minimum_runs: 10)

# This scorer uses custom weights without affecting global config
scorer = WildTestFlakeForensics::Triage::SeverityScorer.new(
  weights: { flake_rate: 2.0, failure_count: 1.0, trend: 0.5, confidence: 1.0 }
)
```

Constructor overrides do not require the global configuration to be frozen. They are useful in testing and in scenarios where you need multiple detector instances with different sensitivity levels.

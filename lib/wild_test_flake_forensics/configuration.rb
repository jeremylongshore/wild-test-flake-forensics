# frozen_string_literal: true

module WildTestFlakeForensics
  class Configuration
    VALID_SEVERITY_WEIGHT_KEYS = %i[flake_rate failure_count trend confidence].freeze

    attr_reader :minimum_runs, :flake_rate_threshold, :max_history_entries, :severity_weights

    def initialize
      @minimum_runs = 3
      @flake_rate_threshold = 0.1
      @max_history_entries = 10_000
      @severity_weights = { flake_rate: 1.0, failure_count: 1.0, trend: 1.0, confidence: 1.0 }
    end

    def minimum_runs=(value)
      check_frozen!
      unless value.is_a?(Integer) && value >= 1
        raise ConfigurationError, "minimum_runs must be a positive integer, got: #{value.inspect}"
      end

      @minimum_runs = value
    end

    def flake_rate_threshold=(value)
      check_frozen!
      unless value.is_a?(Numeric) && value >= 0.0 && value <= 1.0
        raise ConfigurationError, "flake_rate_threshold must be between 0.0 and 1.0, got: #{value.inspect}"
      end

      @flake_rate_threshold = value.to_f
    end

    def max_history_entries=(value)
      check_frozen!
      unless value.is_a?(Integer) && value >= 1
        raise ConfigurationError, "max_history_entries must be a positive integer, got: #{value.inspect}"
      end

      @max_history_entries = value
    end

    def severity_weights=(value)
      check_frozen!
      raise ConfigurationError, "severity_weights must be a Hash, got: #{value.class}" unless value.is_a?(Hash)

      invalid_keys = value.keys - VALID_SEVERITY_WEIGHT_KEYS
      raise ConfigurationError, "severity_weights has invalid keys: #{invalid_keys.inspect}" if invalid_keys.any?

      @severity_weights = { flake_rate: 1.0, failure_count: 1.0, trend: 1.0, confidence: 1.0 }.merge(value)
    end

    def freeze!
      @severity_weights = @severity_weights.freeze
      freeze
    end

    private

    def check_frozen!
      raise FrozenError, "can't modify frozen #{self.class}" if frozen?
    end
  end
end

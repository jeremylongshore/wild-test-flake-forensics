# frozen_string_literal: true

require_relative 'wild_test_flake_forensics/version'
require_relative 'wild_test_flake_forensics/errors'
require_relative 'wild_test_flake_forensics/configuration'

require_relative 'wild_test_flake_forensics/models/test_identity'
require_relative 'wild_test_flake_forensics/models/test_result'
require_relative 'wild_test_flake_forensics/models/root_cause'
require_relative 'wild_test_flake_forensics/models/flake_record'
require_relative 'wild_test_flake_forensics/models/triage_entry'

require_relative 'wild_test_flake_forensics/parsers/base'
require_relative 'wild_test_flake_forensics/parsers/rspec_json'
require_relative 'wild_test_flake_forensics/parsers/junit_xml'
require_relative 'wild_test_flake_forensics/parsers/minitest_json'

require_relative 'wild_test_flake_forensics/detection/comparator'
require_relative 'wild_test_flake_forensics/detection/flake_detector'

require_relative 'wild_test_flake_forensics/analysis/signal_extractors'
require_relative 'wild_test_flake_forensics/analysis/root_cause_analyzer'

require_relative 'wild_test_flake_forensics/triage/severity_scorer'
require_relative 'wild_test_flake_forensics/triage/remediation'
require_relative 'wild_test_flake_forensics/triage/engine'

require_relative 'wild_test_flake_forensics/history/trend_analyzer'
require_relative 'wild_test_flake_forensics/history/store'

require_relative 'wild_test_flake_forensics/export/json_exporter'
require_relative 'wild_test_flake_forensics/export/markdown_exporter'
require_relative 'wild_test_flake_forensics/export/summary_exporter'

module WildTestFlakeForensics
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
      configuration.freeze!
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

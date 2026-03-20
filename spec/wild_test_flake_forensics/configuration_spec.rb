# frozen_string_literal: true

RSpec.describe WildTestFlakeForensics::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'sets minimum_runs to 3' do
      expect(config.minimum_runs).to eq(3)
    end

    it 'sets flake_rate_threshold to 0.1' do
      expect(config.flake_rate_threshold).to eq(0.1)
    end

    it 'sets max_history_entries to 10_000' do
      expect(config.max_history_entries).to eq(10_000)
    end

    it 'sets severity_weights with all 1.0 values' do
      expect(config.severity_weights).to eq(
        flake_rate: 1.0,
        failure_count: 1.0,
        trend: 1.0,
        confidence: 1.0
      )
    end
  end

  describe '#minimum_runs=' do
    it 'accepts a positive integer' do
      config.minimum_runs = 5
      expect(config.minimum_runs).to eq(5)
    end

    it 'raises ConfigurationError for zero' do
      expect { config.minimum_runs = 0 }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end

    it 'raises ConfigurationError for negative' do
      expect { config.minimum_runs = -1 }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end

    it 'raises ConfigurationError for non-integer' do
      expect { config.minimum_runs = 2.5 }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end
  end

  describe '#flake_rate_threshold=' do
    it 'accepts a float between 0 and 1' do
      config.flake_rate_threshold = 0.25
      expect(config.flake_rate_threshold).to eq(0.25)
    end

    it 'accepts 0.0' do
      config.flake_rate_threshold = 0.0
      expect(config.flake_rate_threshold).to eq(0.0)
    end

    it 'accepts 1.0' do
      config.flake_rate_threshold = 1.0
      expect(config.flake_rate_threshold).to eq(1.0)
    end

    it 'raises ConfigurationError for value > 1' do
      expect { config.flake_rate_threshold = 1.5 }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end

    it 'raises ConfigurationError for negative' do
      expect { config.flake_rate_threshold = -0.1 }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end
  end

  describe '#max_history_entries=' do
    it 'accepts a positive integer' do
      config.max_history_entries = 500
      expect(config.max_history_entries).to eq(500)
    end

    it 'raises ConfigurationError for zero' do
      expect { config.max_history_entries = 0 }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end
  end

  describe '#severity_weights=' do
    it 'accepts a valid hash' do
      config.severity_weights = { flake_rate: 2.0, confidence: 0.5 }
      expect(config.severity_weights[:flake_rate]).to eq(2.0)
    end

    it 'raises ConfigurationError for invalid keys' do
      expect { config.severity_weights = { bogus_key: 1.0 } }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end

    it 'raises ConfigurationError for non-Hash' do
      expect { config.severity_weights = 'bad' }
        .to raise_error(WildTestFlakeForensics::ConfigurationError)
    end
  end

  describe '#freeze!' do
    it 'freezes the configuration' do
      config.freeze!
      expect(config).to be_frozen
    end

    it 'raises FrozenError on further mutation' do
      config.freeze!
      expect { config.minimum_runs = 10 }.to raise_error(FrozenError)
    end
  end

  describe 'module-level API' do
    it 'provides a default configuration' do
      expect(WildTestFlakeForensics.configuration).to be_a(described_class)
    end

    it 'yields configuration in configure block' do
      WildTestFlakeForensics.configure do |c|
        c.minimum_runs = 5
      end
      expect(WildTestFlakeForensics.configuration.minimum_runs).to eq(5)
    end

    it 'resets configuration' do
      WildTestFlakeForensics.configuration.minimum_runs = 10
      WildTestFlakeForensics.reset_configuration!
      expect(WildTestFlakeForensics.configuration.minimum_runs).to eq(3)
    end
  end
end

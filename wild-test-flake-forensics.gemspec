# frozen_string_literal: true

require_relative 'lib/wild_test_flake_forensics/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-test-flake-forensics'
  spec.version = WildTestFlakeForensics::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Flaky test detection, root cause analysis, and triage'
  spec.description = 'Library for detecting flaky tests from CI history, correlating ' \
                     'flake signals to likely root causes, and producing structured ' \
                     'triage artifacts for engineering teams.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-test-flake-forensics'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end

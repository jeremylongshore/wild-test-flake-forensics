# frozen_string_literal: true

module WildTestFlakeForensics
  class Error < StandardError; end
  class ParseError < Error; end
  class ConfigurationError < Error; end
  class DetectionError < Error; end
  class ExportError < Error; end
end

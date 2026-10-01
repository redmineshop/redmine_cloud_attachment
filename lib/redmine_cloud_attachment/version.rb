# frozen_string_literal: true

module RedmineCloudAttachment
  # Zeitwerk expects `version.rb` to define `Version` (production eager_load).
  module Version
    STRING = '1.2.3'
  end

  # Alias for Redmine::Plugin.register `version` and existing callers.
  VERSION = Version::STRING
end

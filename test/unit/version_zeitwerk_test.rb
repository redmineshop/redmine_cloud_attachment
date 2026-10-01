# frozen_string_literal: true

require File.expand_path('../../../test/test_helper', __dir__) rescue nil

# Lightweight check without full Redmine test helper when run in isolation.
require_relative '../../lib/redmine_cloud_attachment/version'

class VersionZeitwerkContractTest < Minitest::Test
  def test_version_rb_defines_zeitwerk_constant
    assert defined?(RedmineCloudAttachment::Version)
    assert_equal '1.2.3', RedmineCloudAttachment::Version::STRING
    assert_equal RedmineCloudAttachment::Version::STRING, RedmineCloudAttachment::VERSION
  end
end

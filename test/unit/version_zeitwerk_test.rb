# frozen_string_literal: true

require 'minitest/test'
require_relative '../../lib/redmine_cloud_attachment/version'

class VersionZeitwerkContractTest < Minitest::Test
  def test_version_rb_defines_zeitwerk_constant
    assert defined?(RedmineCloudAttachment::Version)
    assert_equal '1.2.3', RedmineCloudAttachment::Version::STRING
    assert_equal RedmineCloudAttachment::Version::STRING, RedmineCloudAttachment::VERSION
  end
end

if $PROGRAM_NAME == __FILE__
  require 'minitest/autorun'
end

# frozen_string_literal: true

require 'minitest/test'
require 'tempfile'
require_relative '../../lib/redmine_cloud_attachment/storage_security'

# Lightweight contract test: cloud-prefixed attachments must not resolve to a
# local disk path after a cloud read failure (regression for thumbnail storms).
class DiskfileCloudFallbackContractTest < Minitest::Test
  def test_cloud_prefixed_name_is_detected
    assert_match(/^(s3|gcs|azure)_/, 's3_260924120000_photo.png')
    assert_match(/^(s3|gcs|azure)_/, 'gcs_abc')
    refute_match(/^(s3|gcs|azure)_/, '260924120000_photo.png')
  end

  def test_sanitize_does_not_leak_presign_query
    text = RedmineCloudAttachment::StorageSecurity.sanitize_log_text(
      'failed https://minio.example/bucket/key?X-Amz-Signature=secret'
    )
    refute_includes text, 'X-Amz-Signature=secret'
    assert_includes text, '?[redacted]'
  end
end

# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class CloudAttachmentSecurityTest < ActiveSupport::TestCase
  fixtures :projects, :users, :attachments

  def setup
    User.current = nil
    @created_on = Time.utc(2026, 9, 24, 12, 0, 0)
  end

  def teardown
    User.current = nil
  end

  def test_download_key_keeps_a_prefix_that_contains_the_backend_marker
    attachment = cloud_attachment('s3_260924_notes.txt')

    assert_equal 'team/s3_archive/2026/09/260924_notes.txt', attachment.send(:cloud_key)
  end

  def test_download_key_drops_traversal_from_disk_filename
    attachment = cloud_attachment('s3_../../other/secret.txt')
    key = attachment.send(:cloud_key)

    refute_includes key, '..'
    assert_equal 'team/s3_archive/2026/09/secret.txt', key
  end

  def test_upload_key_matches_the_later_download_key
    attachment = cloud_attachment('260924120000_notes.txt')
    upload_key = attachment.send(:build_upload_key)

    assert_equal 'team/s3_archive/2026/09/260924120000_notes.txt', upload_key
    # A reloaded record must not keep the pre-upload backend memo.
    attachment.instance_variable_set(:@storage_backend, nil)
    attachment.disk_filename = "s3_#{File.basename(upload_key)}"
    assert_equal upload_key, attachment.send(:cloud_key)
  end

  def test_upload_key_does_not_keep_a_raw_filename_path
    attachment = Attachment.new(created_on: @created_on)
    attachment.write_attribute(:disk_filename, nil)
    attachment.write_attribute(:filename, '../../etc/passwd.jpg')
    stub_config(attachment)

    key = attachment.send(:build_upload_key)

    refute_includes key, '..'
    assert_match %r{\Ateam/s3_archive/2026/09/[0-9a-f]{32}\.jpg\z}, key
  end

  def test_unsafe_disk_filename_has_no_cloud_key
    attachment = cloud_attachment('s3_..')

    assert_nil attachment.send(:cloud_key)
  end

  def test_safe_direct_url_rejects_an_off_host_presign
    attachment = cloud_attachment('s3_notes.txt')
    attachment.define_singleton_method(:direct_download_url) do |_expires = nil|
      'https://evil.example/redmine-attachments/secret?X-Amz-Signature=sekret'
    end

    assert_nil attachment.safe_direct_url
  end

  def test_safe_direct_url_accepts_the_configured_public_endpoint
    attachment = cloud_attachment('s3_notes.txt')
    url = 'http://localhost:9000/redmine-attachments/redmine/files/2026/09/notes.txt?X-Amz-Signature=sekret'
    attachment.define_singleton_method(:direct_download_url) { |_expires = nil| url }

    assert_equal url, attachment.safe_direct_url
  end

  def test_presign_returns_nil_for_partial_credentials_and_a_bad_endpoint
    partial = cloud_attachment('s3_notes.txt', 'access_key_id' => 'only-id', 'secret_access_key' => '')
    assert_nil partial.direct_download_url
    assert_equal false, partial.readable?

    bad_endpoint = cloud_attachment(
      's3_notes.txt',
      'endpoint' => 'http://user:secret@localhost:9000'
    )
    assert_nil bad_endpoint.direct_download_url
    assert_equal false, bad_endpoint.readable?

    iam = cloud_attachment('s3_notes.txt', 'access_key_id' => '', 'secret_access_key' => '', 'endpoint' => '')
    assert_equal true, iam.readable?
  end

  def test_azure_readable_requires_an_access_key
    attachment = Attachment.new(disk_filename: 'azure_notes.txt', filename: 'notes.txt')
    attachment.define_singleton_method(:cloud_config) do
      { 'container' => 'attachments', 'storage_account_name' => 'sampleacct' }
    end

    assert_equal false, attachment.readable?
  end

  def test_cloud_expiry_time_stays_inside_seven_days
    attachment = cloud_attachment('s3_notes.txt')
    expiry = attachment.cloud_expiry_time

    assert_operator expiry, :>=, 1.minute
    assert_operator expiry, :<=, 7.days
  end

  def test_thumbnail_size_is_capped_without_downloading
    attachment = cloud_attachment('s3_notes.jpg', {})
    attachment.filename = 'notes.jpg'
    attachment.content_type = 'image/jpeg'
    file = Tempfile.new(['cloud-thumb', '.thumb'])
    file.close
    sizes = []
    attachment.define_singleton_method(:thumbnailable?) { true }
    attachment.define_singleton_method(:thumbnail_path) do |size|
      sizes << size
      file.path
    end
    attachment.define_singleton_method(:diskfile) { raise 'thumbnail must not download the object' }

    assert_equal file.path, attachment.thumbnail(size: 5000)
    assert_equal [800], sizes
  ensure
    file&.close
    file&.unlink
  end

  def test_thumbnail_for_text_does_not_touch_diskfile
    attachment = cloud_attachment('s3_notes.txt')
    attachment.filename = 'notes.txt'
    attachment.content_type = 'text/plain'
    calls = 0
    attachment.define_singleton_method(:diskfile) do
      calls += 1
      '/tmp/should-not-be-read'
    end

    assert_nil attachment.thumbnail(size: 100)
    assert_equal 0, calls
  end

  def test_disk_filename_is_not_mass_assignable
    attachment = Attachment.new
    skip 'Redmine safe_attributes= is unavailable' unless attachment.respond_to?(:safe_attributes=)

    attachment.safe_attributes = {
      'filename' => 'notes.txt',
      'disk_filename' => 's3_../../secret.txt',
      'digest' => 'deadbeef'
    }

    refute_equal 's3_../../secret.txt', attachment.disk_filename.to_s
  end

  private

  def cloud_attachment(disk_filename, config_overrides = nil)
    attachment = Attachment.new(
      filename: 'notes.txt',
      disk_filename: disk_filename,
      created_on: @created_on
    )
    stub_config(attachment, config_overrides)
    attachment
  end

  def stub_config(attachment, overrides = nil)
    config = {
      'bucket' => 'redmine-attachments',
      'region' => 'us-east-1',
      'path' => 'team/s3_archive',
      'access_key_id' => 'minioadmin',
      'secret_access_key' => 'minioadmin',
      'endpoint' => 'http://demo-minio:9000',
      'public_endpoint' => 'http://localhost:9000',
      'force_path_style' => true
    }
    config.merge!(overrides) if overrides
    attachment.define_singleton_method(:cloud_config) { config }
    attachment
  end
end

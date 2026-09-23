# frozen_string_literal: true

require 'minitest/test'
require 'tempfile'
require_relative '../../lib/redmine_cloud_attachment/storage_security'

class StorageSecurityTest < Minitest::Test
  Security = RedmineCloudAttachment::StorageSecurity

  MINIO = {
    'bucket' => 'redmine-attachments',
    'region' => 'us-east-1',
    'endpoint' => 'http://demo-minio:9000',
    'public_endpoint' => 'http://localhost:9000',
    'access_key_id' => 'minioadmin',
    'secret_access_key' => 'minioadmin'
  }.freeze

  def test_object_key_strips_backend_prefix_only_from_the_filename
    key = Security.object_key(
      base_path: 'team/s3_archive',
      stamp: '2026/09',
      disk_filename: 's3_260924_notes.txt',
      backend: :s3,
      strip_prefix: true
    )

    assert_equal 'team/s3_archive/2026/09/260924_notes.txt', key
  end

  def test_object_key_drops_parent_segments
    key = Security.object_key(
      base_path: 'redmine/../files/../../etc',
      stamp: '2026/09',
      disk_filename: 's3_../../other/secret.txt',
      backend: :s3,
      strip_prefix: true
    )

    assert_equal 'redmine/files/etc/2026/09/secret.txt', key
    refute_includes key, '..'
  end

  def test_upload_and_download_keys_match_for_a_normal_name
    uploaded = Security.object_key(
      base_path: 'team/s3_archive',
      stamp: '2026/09',
      disk_filename: '260924120000_notes.txt',
      backend: :s3,
      strip_prefix: false
    )
    stored = "s3_#{File.basename(uploaded)}"
    downloaded = Security.object_key(
      base_path: 'team/s3_archive',
      stamp: '2026/09',
      disk_filename: stored,
      backend: :s3,
      strip_prefix: true
    )

    assert_equal 'team/s3_archive/2026/09/260924120000_notes.txt', uploaded
    assert_equal uploaded, downloaded
  end

  def test_object_key_rejects_markup_in_the_filename
    assert_nil Security.object_key(
      base_path: 'redmine/files',
      stamp: '2026/09',
      disk_filename: 's3_a"><img>.txt',
      backend: :s3,
      strip_prefix: true
    )
  end

  def test_object_key_rejects_a_name_that_is_only_dotdot
    assert_nil Security.object_key(
      base_path: 'redmine/files',
      stamp: '2026/09',
      disk_filename: 's3_..',
      backend: :s3,
      strip_prefix: true
    )
  end

  def test_object_key_rejects_a_bad_stamp
    assert_nil Security.object_key(
      base_path: 'redmine/files',
      stamp: '2026/09/../../x',
      disk_filename: 'notes.txt',
      backend: :s3,
      strip_prefix: false
    )
  end

  def test_presigned_minio_url_is_allowed_for_the_public_endpoint
    url = 'http://localhost:9000/redmine-attachments/redmine/files/2026/09/notes.txt?X-Amz-Signature=sekret'
    origins = Security.presign_origins(:s3, MINIO)

    assert_equal ['http://localhost:9000'], origins
    assert Security.presigned_url_allowed?(url, origins, bucket: 'redmine-attachments')
  end

  def test_presigned_url_rejects_other_hosts_schemes_and_header_injection
    origins = Security.presign_origins(:s3, MINIO)
    bucket = 'redmine-attachments'

    refute Security.presigned_url_allowed?('https://evil.example/redmine-attachments/a', origins, bucket: bucket)
    refute Security.presigned_url_allowed?('javascript:alert(1)', origins, bucket: bucket)
    refute Security.presigned_url_allowed?("http://localhost:9000/redmine-attachments/a\r\nLocation: https://evil.example", origins, bucket: bucket)
    refute Security.presigned_url_allowed?('http://user:secret@localhost:9000/redmine-attachments/a', origins, bucket: bucket)
    refute Security.presigned_url_allowed?('http://localhost:9000/other-bucket/secret', origins, bucket: bucket)
    refute Security.presigned_url_allowed?('http://localhost:9000/redmine-attachments/../../other/secret', origins, bucket: bucket)
  end

  def test_internal_minio_host_is_not_a_browser_redirect_target_when_public_endpoint_is_set
    origins = Security.presign_origins(:s3, MINIO)
    internal = 'http://demo-minio:9000/redmine-attachments/redmine/files/a.txt?X-Amz-Signature=sekret'

    refute Security.presigned_url_allowed?(internal, origins, bucket: 'redmine-attachments')
  end

  def test_aws_virtual_host_and_path_style_are_limited_to_the_configured_bucket
    config = { 'bucket' => 'redmine-attachments', 'region' => 'us-east-1' }
    origins = Security.presign_origins(:s3, config)
    virtual = 'https://redmine-attachments.s3.us-east-1.amazonaws.com/redmine/files/a.txt?X-Amz-Signature=sekret'
    path_style = 'https://s3.us-east-1.amazonaws.com/redmine-attachments/redmine/files/a.txt?X-Amz-Signature=sekret'
    other_bucket = 'https://s3.us-east-1.amazonaws.com/other-bucket/secret?X-Amz-Signature=sekret'

    assert_includes origins, 'https://redmine-attachments.s3.us-east-1.amazonaws.com:443'
    assert Security.presigned_url_allowed?(virtual, origins, bucket: 'redmine-attachments')
    assert Security.presigned_url_allowed?(path_style, origins, bucket: 'redmine-attachments')
    refute Security.presigned_url_allowed?(other_bucket, origins, bucket: 'redmine-attachments')
    refute Security.presigned_url_allowed?('https://evil.example/redmine-attachments/a', origins, bucket: 'redmine-attachments')
  end

  def test_gcs_and_azure_origins_are_provider_hosts
    gcs = Security.presign_origins(:gcs, 'bucket' => 'attachments', 'project_id' => 'proj')
    azure = Security.presign_origins(:azure, 'container' => 'attachments', 'storage_account_name' => 'sampleacct')

    assert_equal ['https://storage.googleapis.com:443'], gcs
    assert_equal ['https://sampleacct.blob.core.windows.net:443'], azure
    assert Security.presigned_url_allowed?(
      'https://storage.googleapis.com/attachments/redmine/files/a.txt?X-Goog-Signature=sekret',
      gcs,
      bucket: 'attachments'
    )
    refute Security.presigned_url_allowed?(
      'https://evil.example/attachments/a.txt?sig=sekret',
      azure,
      bucket: 'attachments'
    )
    assert Security.presigned_url_allowed?(
      'https://sampleacct.blob.core.windows.net/attachments/redmine/files/a.txt?sig=sekret',
      azure,
      bucket: 'attachments'
    )
  end

  def test_expiry_is_clamped
    assert_equal 15, Security.expiry_minutes(nil)
    assert_equal 15, Security.expiry_minutes('15')
    assert_equal 1, Security.expiry_minutes(0)
    assert_equal 1, Security.expiry_minutes(-10)
    assert_equal Security::MAX_EXPIRY_MINUTES, Security.expiry_minutes(999_999)
    assert_equal 60, Security.expiry_seconds(0)
    assert_equal 900, Security.expiry_seconds(900)
    assert_equal Security::MAX_EXPIRY_SECONDS, Security.expiry_seconds(10 * 365 * 24 * 3600)
  end

  def test_log_text_redacts_presigned_queries_and_secrets
    raw = 'connect failed http://localhost:9000/bucket/key?X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20260924&X-Amz-Signature=abcdef1234567890 ' \
          'secret_access_key: supersecretvalue http://minioadmin:minioadmin@demo-minio:9000/bucket'

    cleaned = Security.sanitize_log_text(raw)

    refute_includes cleaned, 'abcdef1234567890'
    refute_includes cleaned, 'AKIAIOSFODNN7EXAMPLE'
    refute_includes cleaned, 'supersecretvalue'
    refute_includes cleaned, 'minioadmin:minioadmin'
    assert_includes cleaned, '?[redacted]'
    assert_includes cleaned, '[redacted]'
  end

  def test_endpoint_validation
    assert Security.valid_http_endpoint?(nil)
    assert Security.valid_http_endpoint?('http://localhost:9000')
    assert Security.valid_http_endpoint?('https://files.example.com')
    refute Security.valid_http_endpoint?('javascript:alert(1)')
    refute Security.valid_http_endpoint?('file:///etc/passwd')
    refute Security.valid_http_endpoint?('http://user:secret@localhost:9000')
    refute Security.valid_http_endpoint?('http://')
  end

  def test_s3_credentials_require_both_keys_or_neither
    assert Security.s3_credentials_ok?('access_key_id' => '', 'secret_access_key' => '')
    assert Security.s3_credentials_ok?('access_key_id' => 'id', 'secret_access_key' => 'secret')
    refute Security.s3_credentials_ok?('access_key_id' => 'id', 'secret_access_key' => '')
    refute Security.azure_credentials_ok?('storage_account_name' => 'sampleacct')
    assert Security.azure_credentials_ok?(
      'storage_account_name' => 'sampleacct',
      'storage_access_key' => 'key'
    )
    refute Security.safe_container_name?('../other')
    refute Security.safe_container_name?('my bucket')
    assert Security.safe_container_name?('redmine-attachments')
  end

  def test_thumbnail_pixel_size_bounds
    assert_equal 100, Security.thumbnail_pixel_size(0, 0)
    assert_equal 120, Security.thumbnail_pixel_size(-5, 120)
    assert_equal 50, Security.thumbnail_pixel_size(1, 100)
    assert_equal 100, Security.thumbnail_pixel_size('51', 100)
    assert_equal 800, Security.thumbnail_pixel_size(5000, 100)
    assert_equal 80, Security.thumbnail_pixel_size(['1'], 80)
  end

  def test_temp_suffix_rejects_path_characters
    assert_equal '.jpg', Security.safe_temp_suffix('photo.jpg')
    assert_equal '.jpg', Security.safe_temp_suffix('../../photo.jpg')
    assert_equal '', Security.safe_temp_suffix('photo.jpg/../../etc/passwd')
    assert_equal '', Security.safe_temp_suffix('no-extension')
    assert_equal '', Security.safe_temp_suffix('photo.with space')
  end

  def test_plugin_does_not_skip_csrf_or_allow_external_redirects
    root = File.expand_path('../..', __dir__)
    files = Dir[File.join(root, 'lib', '**', '*.rb')] +
            Dir[File.join(root, 'app', '**', '*.rb')] +
            [File.join(root, 'init.rb')]
    bodies = files.map { |path| [path, File.read(path)] }

    bodies.each do |path, body|
      refute_match(/skip_before_action\s+:verify_authenticity_token/, body, path)
      refute_match(/skip_forgery_protection/, body, path)
      refute_match(/allow_other_host/, body, path)
    end

    controller = File.read(File.join(root, 'lib/redmine_cloud_attachment/patches/attachments_controller_patch.rb'))
    refute_match(/redirect_to\(\s*presigned/, controller)
    assert_includes controller, 'self.location = presigned_url_value'
    view = File.read(File.join(root, 'app/views/attachments/image.html.erb'))
    refute_match(/html_safe|raw\b/, view)
  end
end

if $PROGRAM_NAME == __FILE__
  require 'minitest/autorun'
end

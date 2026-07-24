require File.expand_path('../../test_helper', __FILE__)

class BasicFunctionalityTest < ActiveSupport::TestCase
  fixtures :projects, :users, :attachments

  def setup
    User.current = nil
  end

  def teardown
    User.current = nil
  end

  def test_plugin_loaded_correctly
    # Test that the plugin is loaded
    assert Redmine::Plugin.registered_plugins.has_key?(:redmine_cloud_attachment), 
           "Plugin should be registered"
  end

  def test_attachment_model_has_cloud_methods
    attachment = Attachment.new
    
    # Test that cloud methods are available
    assert attachment.respond_to?(:cloud_diskfile?), "Should have cloud_diskfile? method"
    assert attachment.respond_to?(:direct_download_url), "Should have direct_download_url method"
    assert attachment.respond_to?(:storage_backend), "Should have storage_backend method"
  end

  def test_basic_attachment_functionality
    # Create a basic attachment for testing
    attachment = Attachment.create!(
      filename: 'test.txt',
      disk_filename: 'test_123.txt',
      filesize: 100,
      content_type: 'text/plain',
      digest: 'abc123',
      author_id: 1
    )
    
    assert attachment.persisted?, "Attachment should be saved"
    assert_equal 'test.txt', attachment.filename
    assert_equal :local, attachment.storage_backend
    assert_not attachment.cloud_diskfile?
  end

  def test_cloud_attachment_detection
    # Test S3 attachment
    s3_attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 's3_test_123.txt',
      filesize: 100,
      content_type: 'text/plain',
      digest: 'abc123'
    )
    
    assert_equal :s3, s3_attachment.storage_backend
    assert s3_attachment.cloud_diskfile?
    
    # Test GCS attachment  
    gcs_attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 'gcs_test_123.txt',
      filesize: 100,
      content_type: 'text/plain',
      digest: 'abc123'
    )
    
    assert_equal :gcs, gcs_attachment.storage_backend
    assert gcs_attachment.cloud_diskfile?
    
    # Test Azure attachment
    azure_attachment = Attachment.new(
      filename: 'test.txt', 
      disk_filename: 'azure_test_123.txt',
      filesize: 100,
      content_type: 'text/plain',
      digest: 'abc123'
    )
    
    assert_equal :azure, azure_attachment.storage_backend
    assert azure_attachment.cloud_diskfile?
  end

  def test_direct_download_url_for_local_attachment
    local_attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 'test_123.txt'
    )
    
    # Local attachments should return nil for direct download URL
    assert_nil local_attachment.direct_download_url
  end

  def test_readable_method_for_cloud_attachments
    cloud_attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 's3_test_123.txt'
    )
    
    # Should not call diskfile() for readable check on cloud attachments
    # Instead should check cloud configuration
    result = cloud_attachment.readable?
    assert [true, false].include?(result), "readable? should return boolean"
  end

  def test_local_readable_delegates_to_core_via_super
    attachment = Attachment.new(
      filename: 'local.jpg',
      disk_filename: '260724_local.jpg',
      content_type: 'image/jpeg'
    )

    assert_not attachment.cloud_diskfile?
    assert attachment.method(:readable?).owner == RedmineCloudAttachment::AttachmentPatch
    assert_not_nil attachment.method(:readable?).super_method,
                   'prepend must keep Attachment#readable? reachable via super'
    # Without a real file this is false, but must not raise NoMethodError
    assert_equal false, attachment.readable?
  end

  def test_azure_credential_helpers_accept_sample_and_legacy_keys
    attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 'azure_test_123.txt'
    )

    attachment.define_singleton_method(:cloud_config) do
      {
        'container' => 'attachments',
        'storage_account_name' => 'sampleacct',
        'storage_access_key' => 'samplekey'
      }
    end
    assert_equal 'sampleacct', attachment.send(:azure_account_name)
    assert_equal 'samplekey', attachment.send(:azure_access_key)

    attachment.define_singleton_method(:cloud_config) do
      {
        'container' => 'attachments',
        'account_name' => 'legacyacct',
        'access_key' => 'legacykey'
      }
    end
    assert_equal 'legacyacct', attachment.send(:azure_account_name)
    assert_equal 'legacykey', attachment.send(:azure_access_key)
  end

  def test_thumbnailable_for_image_attachments
    image_attachment = Attachment.new(
      filename: 'test.jpg',
      disk_filename: 's3_test_123.jpg',
      content_type: 'image/jpeg'
    )

    assert image_attachment.thumbnailable?, 'Image attachment should be thumbnailable'

    text_attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 's3_test_123.txt',
      content_type: 'text/plain'
    )

    assert_not text_attachment.thumbnailable?, 'Text attachment should not be thumbnailable'
  end

  def test_s3_client_options_include_minio_endpoint
    attachment = Attachment.new(disk_filename: 's3_test.txt')
    attachment.define_singleton_method(:cloud_config) do
      {
        'bucket' => 'redmine-attachments',
        'region' => 'us-east-1',
        'access_key_id' => 'minioadmin',
        'secret_access_key' => 'minioadmin',
        'endpoint' => 'http://demo-minio:9000',
        'public_endpoint' => 'http://localhost:9000',
        'force_path_style' => true
      }
    end

    opts = attachment.send(:s3_client_options)
    assert_equal 'http://demo-minio:9000', opts[:endpoint]
    assert_equal true, opts[:force_path_style]
    assert_equal 'us-east-1', opts[:region]

    public_opts = attachment.send(:s3_client_options, endpoint: 'http://localhost:9000')
    assert_equal 'http://localhost:9000', public_opts[:endpoint]
    assert_equal true, public_opts[:force_path_style]
  end
end

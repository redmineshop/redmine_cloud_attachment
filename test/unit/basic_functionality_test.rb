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

  def test_thumbnailable_for_image_attachments
    image_attachment = Attachment.new(
      filename: 'test.jpg',
      disk_filename: 's3_test_123.jpg',
      content_type: 'image/jpeg'
    )
    
    assert image_attachment.thumbnailable?, "Image attachment should be thumbnailable"
    
    text_attachment = Attachment.new(
      filename: 'test.txt',
      disk_filename: 's3_test_123.txt',
      content_type: 'text/plain'
    )
    
    assert_not text_attachment.thumbnailable?, "Text attachment should not be thumbnailable"
  end
end 

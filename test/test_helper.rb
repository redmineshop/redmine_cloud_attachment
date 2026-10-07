# Load the Redmine helper
require_relative '../../../test/test_helper'

# Ensure plugin is loaded for tests - không cần load init.rb vì Redmine sẽ auto-load plugins
# require_relative '../init'

# Helper methods for cloud attachment tests
module CloudAttachmentTestHelper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def skip_without_cloud_attachments
      setup do
        cloud_attachments = Attachment.where("disk_filename LIKE 's3_%' OR disk_filename LIKE 'gcs_%' OR disk_filename LIKE 'azure_%'")
        skip "No cloud attachments available for testing" if cloud_attachments.empty?
      end
    end

    def skip_without_imagemagick
      setup do
        skip "ImageMagick convert not available" unless Redmine::Thumbnail.convert_available?
      end
    end

    def skip_without_ghostscript
      setup do
        skip "Ghostscript not available" unless Redmine::Thumbnail.gs_available?
      end
    end
  end

  def find_cloud_attachment(type: :any)
    query = Attachment.where("disk_filename LIKE 's3_%' OR disk_filename LIKE 'gcs_%' OR disk_filename LIKE 'azure_%'")
    
    case type
    when :image
      query = query.where("filename LIKE '%.png' OR filename LIKE '%.jpg' OR filename LIKE '%.jpeg' OR filename LIKE '%.gif'")
    when :pdf
      query = query.where("filename LIKE '%.pdf'")
    when :non_image
      query = query.where.not("filename LIKE '%.png' OR filename LIKE '%.jpg' OR filename LIKE '%.jpeg' OR filename LIKE '%.gif'")
    end
    
    query.first
  end

  def cleanup_test_thumbnails(attachment = nil)
    thumbnails_dir = Attachment.thumbnails_storage_path
    return unless Dir.exist?(thumbnails_dir)
    
    pattern = if attachment&.digest
                File.join(thumbnails_dir, "#{attachment.digest}_*.thumb")
              else
                File.join(thumbnails_dir, "*.thumb")
              end
    
    Dir.glob(pattern).each do |file|
      File.delete(file) rescue nil
    end
  end

  def with_redmine_config(settings)
    config = Redmine::Configuration.instance_variable_get(:@config)
    raise 'Redmine configuration is not loaded' unless config

    replacement = {}
    settings.each { |key, value| replacement[key.to_s] = value }
    previous = replacement.keys.to_h { |key| [key, config[key]] }
    config.merge!(replacement)
    yield
  ensure
    config.merge!(previous) if config && previous
  end

  def with_tmp_attachments_directory
    previous = Attachment.storage_path
    set_tmp_attachments_directory
    FileUtils.mkdir_p(Attachment.storage_path)
    yield
  ensure
    Attachment.storage_path = previous if previous
  end

  def clear_cloud_attachment_stubs
    Thread.current[:rca_stub_url] = nil
    Thread.current[:rca_direct_url] = nil
    Thread.current[:rca_stub_config] = nil
    Thread.current[:rca_cloud_config] = nil
    Thread.current[:rca_stub_diskfile] = nil
    Thread.current[:rca_diskfile] = nil
  end
end

# Test doubles. A flag must be set or the real cloud methods run.
module CloudAttachmentTestStub
  def direct_download_url(*)
    return Thread.current[:rca_direct_url] if Thread.current[:rca_stub_url]

    super
  end

  def cloud_config
    return Thread.current[:rca_cloud_config] if Thread.current[:rca_stub_config]

    super
  end

  def diskfile
    return Thread.current[:rca_diskfile] if Thread.current[:rca_stub_diskfile]

    super
  end
end

Attachment.prepend(CloudAttachmentTestStub) unless Attachment.ancestors.include?(CloudAttachmentTestStub)

# Include helper in all test cases
ActiveSupport::TestCase.include CloudAttachmentTestHelper
ActiveSupport::TestCase.setup { clear_cloud_attachment_stubs }
ActiveSupport::TestCase.teardown { clear_cloud_attachment_stubs }

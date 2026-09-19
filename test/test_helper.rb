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
end

# Include helper in all test cases
ActiveSupport::TestCase.include CloudAttachmentTestHelper

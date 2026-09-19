# frozen_string_literal: true

require 'redmine'
require_dependency 'redmine/plugin'
require_relative 'lib/redmine_cloud_attachment/version'

Redmine::Plugin.register :redmine_cloud_attachment do
  name 'Redmine Cloud Attachment'
  author 'RedmineShop (based on railsfactory/redmine_cloud_attachment_pro)'
  description 'Store Redmine attachments in AWS S3, Google Cloud Storage, or Azure Blob — with presigned URL support for secure direct downloads.'
  version RedmineCloudAttachment::VERSION
  url 'https://redmineshop.com/products/redmine-cloud-attachment'
  author_url 'https://redmineshop.com'
end

module RedmineCloudAttachment
  module Boot
    module_function

    def apply_patches
      plugin_dir = Redmine::Plugin.find(:redmine_cloud_attachment).directory

      require_dependency File.join(plugin_dir, 'lib', 'redmine_cloud_attachment', 'attachment_patch')
      require_dependency File.join(
        plugin_dir, 'lib', 'redmine_cloud_attachment', 'patches', 'attachments_controller_patch'
      )
      require_dependency File.join(
        plugin_dir, 'lib', 'redmine_cloud_attachment', 'patches', 'attachments_helper_patch'
      )

      unless Attachment.ancestors.include?(RedmineCloudAttachment::AttachmentPatch)
        Attachment.prepend RedmineCloudAttachment::AttachmentPatch
      end

      unless AttachmentsController.ancestors.include?(
        RedmineCloudAttachment::Patches::AttachmentsControllerPatch
      )
        AttachmentsController.prepend RedmineCloudAttachment::Patches::AttachmentsControllerPatch
      end

      unless AttachmentsHelper.ancestors.include?(
        RedmineCloudAttachment::Patches::AttachmentsHelperPatch
      )
        AttachmentsHelper.prepend RedmineCloudAttachment::Patches::AttachmentsHelperPatch
      end
    end
  end
end

# Zeitwerk (Redmine 6+): apply after full boot. Classic: re-apply on each reload.
if Rails.version > '6.0' && Rails.autoloaders.zeitwerk_enabled?
  Rails.application.config.after_initialize do
    RedmineCloudAttachment::Boot.apply_patches
  end
else
  reloader = Rails.version > '5' ? ActiveSupport::Reloader : ActionDispatch::Callbacks
  reloader.to_prepare do
    RedmineCloudAttachment::Boot.apply_patches
  end
end

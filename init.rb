# frozen_string_literal: true

require 'redmine'
require_dependency 'redmine/plugin'
require_relative 'lib/redmine_cloud_attachment/version'

Redmine::Plugin.register :redmine_cloud_attachment do
  name 'Redmine Cloud Attachment'
  author 'RedmineShop (based on railsfactory/redmine_cloud_attachment)'
  description 'Store Redmine attachments in AWS S3, Google Cloud Storage, or Azure Blob — with presigned URL support for secure direct downloads.'
  version RedmineCloudAttachment::VERSION
  url 'https://redmineshop.com/products/redmine-cloud-attachment'
  author_url 'https://redmineshop.com'

  # Rails.logger.info "[CloudAttachment INIT] Inside plugin registration block."

  # Plugin settings definition (if any)
  # settings default: { 'setting_key' => 'default_value' }, partial: 'settings/rcap_settings'

  # Rails.logger.info "[CloudAttachment INIT] Attempting to load and apply patches directly."

  # Ensure Attachment class is loaded before patching
  begin
    require_dependency 'attachment' # Core Redmine class
    patch_module_fqn = 'RedmineCloudAttachment::AttachmentPatch'
    patch_file_path = File.join(File.dirname(__FILE__), 'lib', 'redmine_cloud_attachment', 'attachment_patch.rb')
    # Rails.logger.info "[CloudAttachment INIT] Requiring AttachmentPatch from: #{patch_file_path}"
    require_dependency patch_file_path
    # Rails.logger.info "[CloudAttachment INIT] Successfully required AttachmentPatch."

    patch_module = patch_module_fqn.constantize
    target_class = Attachment

    unless target_class.included_modules.include?(patch_module)
      target_class.send(:include, patch_module)
      # Rails.logger.info "[CloudAttachment INIT] Successfully patched Attachment model with #{patch_module_fqn}."
    # else
      # Rails.logger.info "[CloudAttachment INIT] Attachment model already includes #{patch_module_fqn}."
    end
  rescue LoadError => e
    Rails.logger.error "[CloudAttachment] Error loading/applying AttachmentPatch. Message: #{e.message}"
  rescue NameError => e
    Rails.logger.error "[CloudAttachment] Error finding Attachment or AttachmentPatch module. Message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[CloudAttachment] General error applying AttachmentPatch. Message: #{e.message}"
  end

  # Ensure AttachmentsController is loaded before patching
  begin
    require_dependency 'attachments_controller' # Core Redmine class
    controller_patch_fqn = 'RedmineCloudAttachment::Patches::AttachmentsControllerPatch'
    controller_patch_path = File.join(File.dirname(__FILE__), 'lib', 'redmine_cloud_attachment', 'patches', 'attachments_controller_patch.rb')
    # Rails.logger.info "[CloudAttachment INIT] Requiring AttachmentsControllerPatch from: #{controller_patch_path}"
    require_dependency controller_patch_path
    # Rails.logger.info "[CloudAttachment INIT] Successfully required AttachmentsControllerPatch."

    patch_module = controller_patch_fqn.constantize
    target_controller = AttachmentsController

    unless target_controller.included_modules.include?(patch_module)
      target_controller.send(:include, patch_module) # Using include, ensure patch uses `included do` or `prepended do` as appropriate
      # Rails.logger.info "[CloudAttachment INIT] Successfully patched AttachmentsController with #{controller_patch_fqn}."
    # else
      # Rails.logger.info "[CloudAttachment INIT] AttachmentsController already includes #{controller_patch_fqn}."
    end
  rescue LoadError => e
    Rails.logger.error "[CloudAttachment] Error loading/applying AttachmentsControllerPatch. Message: #{e.message}"
  rescue NameError => e
    Rails.logger.error "[CloudAttachment] Error finding AttachmentsController or its patch module. Message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[CloudAttachment] General error applying AttachmentsControllerPatch. Message: #{e.message}"
  end

  # Ensure AttachmentsHelper is loaded before patching
  begin
    require_dependency 'attachments_helper' # Core Redmine helper
    helper_patch_fqn = 'RedmineCloudAttachment::Patches::AttachmentsHelperPatch'
    helper_patch_path = File.join(File.dirname(__FILE__), 'lib', 'redmine_cloud_attachment', 'patches', 'attachments_helper_patch.rb')
    require_dependency helper_patch_path

    patch_module = helper_patch_fqn.constantize
    target_helper = AttachmentsHelper

    unless target_helper.included_modules.include?(patch_module)
      target_helper.send(:include, patch_module)
      Rails.logger.debug "[CloudAttachment] Successfully patched AttachmentsHelper with #{helper_patch_fqn}."
    end

    # Also patch ApplicationHelper for thumbnail_path method
    ApplicationHelper.send(:include, patch_module) unless ApplicationHelper.included_modules.include?(patch_module)
  rescue LoadError => e
    Rails.logger.error "[CloudAttachment] Error loading/applying AttachmentsHelperPatch. Message: #{e.message}"
  rescue NameError => e
    Rails.logger.error "[CloudAttachment] Error finding AttachmentsHelper or its patch module. Message: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "[CloudAttachment] General error applying AttachmentsHelperPatch. Message: #{e.message}"
  end

  # Note: optimization_test.rb moved to test/ directory

  # Rails.logger.info "[CloudAttachment INIT] Exiting plugin registration block after attempting direct patch loading."
end

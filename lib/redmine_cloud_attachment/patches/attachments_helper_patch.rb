module RedmineCloudAttachment
  module Patches
    module AttachmentsHelperPatch
      extend ActiveSupport::Concern

      included do
        # Override render_api_attachment_attributes to use direct cloud URLs when available
        alias_method :original_render_api_attachment_attributes, :render_api_attachment_attributes

        def render_api_attachment_attributes(attachment, api)
          original_render_api_attachment_attributes(attachment, api)
          
          # Add direct download URL for cloud attachments if available
          if attachment.respond_to?(:direct_download_url) && attachment.respond_to?(:cloud_diskfile?) && attachment.cloud_diskfile?
            expires_in = attachment.cloud_expiry_time
            direct_url = attachment.direct_download_url(expires_in)
            if direct_url
              api.direct_content_url direct_url
              Rails.logger.debug "[CloudAttachment] Added direct cloud URL to API response for attachment #{attachment.id}"
            end
          end
        end

        # Note: We no longer override thumbnail_path as we now generate real thumbnails for cloud attachments
        # The thumbnail method in attachment_patch.rb handles cloud file thumbnails properly
      end
    end
  end
end 

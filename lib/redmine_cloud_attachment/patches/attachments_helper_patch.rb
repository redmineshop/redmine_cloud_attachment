# frozen_string_literal: true

module RedmineCloudAttachment
  module Patches
    module AttachmentsHelperPatch
      def render_api_attachment_attributes(attachment, api)
        super

        return unless attachment.respond_to?(:cloud_diskfile?) && attachment.cloud_diskfile?

        direct_url = attachment.respond_to?(:safe_direct_url) ? attachment.safe_direct_url : nil
        return unless direct_url

        api.direct_content_url direct_url
      end
    end
  end
end

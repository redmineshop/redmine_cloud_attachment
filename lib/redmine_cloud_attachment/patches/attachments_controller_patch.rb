# frozen_string_literal: true

require_relative '../storage_security'

module RedmineCloudAttachment
  module Patches
    module AttachmentsControllerPatch
      def download
        if @attachment&.respond_to?(:safe_direct_url) && @attachment.cloud_diskfile?
          presigned_url_value = @attachment.safe_direct_url

          if presigned_url_value
            begin
              if @attachment.container.is_a?(Version) || @attachment.container.is_a?(Project)
                @attachment.increment_download
              end

              # Set Location directly. redirect_to logs the full URL, and a
              # presigned URL is a time-limited credential.
              Rails.logger.info(
                "[CloudAttachment] Redirecting attachment ##{@attachment.id} to configured cloud storage"
              )
              self.status = 302
              self.location = presigned_url_value
              self.response_body = ''
              return
            rescue StandardError => e
              Rails.logger.error(
                "[CloudAttachment] Presigned redirect failed for ##{@attachment&.id}: " \
                "#{RedmineCloudAttachment::StorageSecurity.sanitize_log_text(e.message)}. Falling back."
              )
            end
          else
            Rails.logger.warn(
              "[CloudAttachment] No usable presigned URL for attachment ##{@attachment.id}, falling back"
            )
          end

          if @attachment.diskfile.blank?
            render_404
            return
          end
        end

        super
      end

      def show
        if @attachment&.respond_to?(:cloud_diskfile?) && @attachment.cloud_diskfile?
          if @attachment.is_image? && @attachment.respond_to?(:safe_direct_url)
            @direct_url = @attachment.safe_direct_url
          elsif request.format.html? && cloud_preview_needs_bytes? && @attachment.diskfile.blank?
            render_404
            return
          end
        end

        super
      end

      def find_downloadable_attachments
        return unless defined?(@container) && @container

        # Same gate as Redmine core. Project#visible? is view_project;
        # attachments_visible? also requires view_files (and the files module).
        unless @container.try(:attachments_visible?)
          deny_access
          return
        end

        @attachments = @container.attachments.select(&:readable?)

        bulk_download_max_size = Setting.bulk_download_max_size.to_i.kilobytes
        return unless @attachments.sum(&:filesize) > bulk_download_max_size

        flash[:error] = l(
          :error_bulk_download_size_too_big,
          max_size: number_to_human_size(bulk_download_max_size.to_i)
        )
        # Same-origin only. The Referer header is attacker-controlled.
        redirect_to(container_url)
        return
      end

      def file_readable
        if @attachment.respond_to?(:cloud_diskfile?) && @attachment.cloud_diskfile?
          return true if @attachment.readable?

          Rails.logger.error("[CloudAttachment] Cloud attachment #{@attachment.id} is not accessible")
          render_404
        elsif @attachment.readable?
          true
        else
          logger.error "Cannot send attachment, #{@attachment.diskfile} does not exist or is unreadable."
          render_404
        end
      end

      private

      def cloud_preview_needs_bytes?
        return false unless @attachment
        # Rouge treats .pdf as a lexer, so Attachment#is_text? is true for PDFs.
        # The PDF preview embeds a download path and does not read the object.
        return false if @attachment.is_pdf? || @attachment.is_image?

        @attachment.is_diff? ||
          (@attachment.is_text? && @attachment.filesize.to_i <= Setting.file_max_size_displayed.to_i.kilobyte)
      end
    end
  end
end

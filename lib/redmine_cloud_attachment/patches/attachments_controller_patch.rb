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
        end

        super
      end

      def show
        unless @attachment&.respond_to?(:cloud_diskfile?) && @attachment.cloud_diskfile?
          return super
        end

        respond_to do |format|
          format.html do
            if @attachment.container.respond_to?(:attachments)
              @attachments = @attachment.container.attachments.to_a
              if (index = @attachments.index(@attachment))
                @paginator = Redmine::Pagination::Paginator.new(@attachments.size, 1, index + 1)
              end
            end

            if @attachment.is_diff?
              @diff = File.read(@attachment.diskfile, mode: 'rb')
              @diff_type = params[:type] || User.current.pref[:diff_type] || 'inline'
              @diff_type = 'inline' unless %w[inline sbs].include?(@diff_type)
              if User.current.logged? && @diff_type != User.current.pref[:diff_type]
                User.current.pref[:diff_type] = @diff_type
                User.current.preference.save
              end
              render action: 'diff'
            elsif @attachment.is_text? && @attachment.filesize <= Setting.file_max_size_displayed.to_i.kilobyte
              @content = File.read(@attachment.diskfile, mode: 'rb')
              render action: 'file'
            elsif @attachment.is_image?
              @direct_url = @attachment.safe_direct_url if @attachment.respond_to?(:safe_direct_url)
              render action: 'image'
            else
              render action: 'other'
            end
          end
          format.api
        end
      end

      def find_downloadable_attachments
        return unless defined?(@container) && @container

        @attachments = @container.attachments.select do |attachment|
          if attachment.respond_to?(:cloud_diskfile?) && attachment.cloud_diskfile?
            attachment.disk_filename.present?
          else
            attachment.readable?
          end
        end

        bulk_download_max_size = Setting.bulk_download_max_size.to_i.kilobytes
        return unless @attachments.sum(&:filesize) > bulk_download_max_size

        flash[:error] = l(
          :error_bulk_download_size_too_big,
          max_size: number_to_human_size(bulk_download_max_size.to_i)
        )
        # Same-origin only. The Referer header is attacker-controlled.
        redirect_to(container_url)
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
    end
  end
end

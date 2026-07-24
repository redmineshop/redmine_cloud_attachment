# Rails.logger.info "[CloudAttachment LOAD] Attempting to load AttachmentsControllerPatch file: #{__FILE__}"
module RedmineCloudAttachment
  module Patches
    module AttachmentsControllerPatch
      extend ActiveSupport::Concern

      included do
        # Store the original methods
        alias_method :original_download_for_cloud_pro, :download
        alias_method :original_show_for_cloud_pro, :show

        # Override the download method
        def download
          # @attachment is typically set by a before_action like :find_attachment or :file_readable
          # The presigned URL logic below should only apply if the user has rights to view/download the attachment.
          # Basic check for @attachment and respond_to?(:direct_download_url) is done before calling direct_download_url.

          if @attachment&.respond_to?(:direct_download_url) && @attachment.respond_to?(:cloud_diskfile?) && @attachment.cloud_diskfile?
            # Get configurable expiry time (default 15 minutes)
            expires_in = @attachment.cloud_expiry_time
            presigned_url_value = @attachment.direct_download_url(expires_in)

            if presigned_url_value
              begin
                Rails.logger.info "[CloudAttachment] Redirecting to presigned URL for attachment ##{@attachment.id} (#{@attachment.filename}) - offloading to cloud storage"
                
                # Update download counter for project/version attachments
                if @attachment.container.is_a?(Version) || @attachment.container.is_a?(Project)
                  @attachment.increment_download
                end

                redirect_to presigned_url_value, allow_other_host: true
                return # Crucial to prevent original_download_for_cloud_pro from executing
              rescue => e
                Rails.logger.error "[CloudAttachment] Error during presigned URL redirect for attachment ##{@attachment&.id}: #{e.message}. Falling back to normal download."
                # Fall through to original_download_for_cloud_pro
              end
            else
              Rails.logger.warn "[CloudAttachment] Failed to generate presigned URL for attachment ##{@attachment.id}, falling back to normal download"
            end
          end

          # If no presigned URL, or an error occurred, or attachment doesn't support it,
          # or if the @attachment conditions were not met, call original download method.
          Rails.logger.debug "[CloudAttachment] Using original download method for attachment ##{@attachment&.id}"
          original_download_for_cloud_pro
        end

        # Override show method to optimize cloud file display
        def show
          # For cloud files that need content reading (text files, diffs), we still need to download
          # But we can optimize by only doing this when necessary
          if @attachment&.respond_to?(:cloud_diskfile?) && @attachment.cloud_diskfile?
            Rails.logger.debug "[CloudAttachment] Processing show request for cloud attachment ##{@attachment.id} (#{@attachment.filename})"
            
            respond_to do |format|
              format.html do
                if @attachment.container.respond_to?(:attachments)
                  @attachments = @attachment.container.attachments.to_a
                  if index = @attachments.index(@attachment)
                    @paginator = Redmine::Pagination::Paginator.new(
                      @attachments.size, 1, index+1
                    )
                  end
                end
                
                # For diff and text files, we need to download content
                if @attachment.is_diff?
                  Rails.logger.info "[CloudAttachment] Downloading diff content from cloud for attachment ##{@attachment.id}"
                  @diff = File.read(@attachment.diskfile, :mode => "rb")
                  @diff_type = params[:type] || User.current.pref[:diff_type] || 'inline'
                  @diff_type = 'inline' unless %w(inline sbs).include?(@diff_type)
                  # Save diff type as user preference
                  if User.current.logged? && @diff_type != User.current.pref[:diff_type]
                    User.current.pref[:diff_type] = @diff_type
                    User.current.preference.save
                  end
                  render :action => 'diff'
                elsif @attachment.is_text? && @attachment.filesize <= Setting.file_max_size_displayed.to_i.kilobyte
                  Rails.logger.info "[CloudAttachment] Downloading text content from cloud for attachment ##{@attachment.id}"
                  @content = File.read(@attachment.diskfile, :mode => "rb")
                  render :action => 'file'
                elsif @attachment.is_image?
                  # For images, we can directly show the cloud URL if available
                  expires_in = @attachment.cloud_expiry_time
                  @direct_url = @attachment.direct_download_url(expires_in)
                  Rails.logger.debug "[CloudAttachment] Using direct cloud URL for image display: #{@direct_url.present?}"
                  render :action => 'image'
                else
                  render :action => 'other'
                end
              end
              format.api
            end
            return
          end

          # Fall back to original show method for local files
          original_show_for_cloud_pro
        end

        # Override find_downloadable_attachments to avoid calling readable? which triggers diskfile()
        def find_downloadable_attachments
          if defined?(@container) && @container
            # For cloud attachments, skip the expensive readable? check
            # We'll trust that cloud-stored files are readable via cloud storage
            @attachments = @container.attachments.select do |attachment|
              if attachment.respond_to?(:cloud_diskfile?) && attachment.cloud_diskfile?
                attachment.disk_filename.present? # Simple check without file system access
              else
                attachment.readable? # Normal check for local files
              end
            end
            
            bulk_download_max_size = Setting.bulk_download_max_size.to_i.kilobytes
            if @attachments.sum(&:filesize) > bulk_download_max_size
              flash[:error] = l(:error_bulk_download_size_too_big,
                                :max_size => number_to_human_size(bulk_download_max_size.to_i))
              redirect_back_or_default(container_url, referer: true)
              return
            end
          end
        end

        # Override file_readable to avoid diskfile() check for cloud attachments  
        def file_readable
          if @attachment.respond_to?(:cloud_diskfile?) && @attachment.cloud_diskfile?
            # For cloud files, use optimized readable? check that doesn't call diskfile()
            if @attachment.readable?
              true
            else
              Rails.logger.error "[CloudAttachment] Cloud attachment #{@attachment.id} is not accessible"
              render_404
            end
          else
            # Use original logic for local files
            if @attachment.readable?
              true
            else
              logger.error "Cannot send attachment, #{@attachment.diskfile} does not exist or is unreadable."
              render_404
            end
          end
        end
      end
    end
  end
end 

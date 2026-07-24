require 'aws-sdk-s3'
require 'google/cloud/storage'
require 'azure/storage/blob'
require_dependency 'attachment'

module RedmineCloudAttachment
  module AttachmentPatch
    def self.included(base)
      base.class_eval do
        after_destroy :delete_from_cloud
        before_destroy :cleanup_temp_file

        # Method to generate a direct download URL (e.g., S3 presigned URL)
        # Returns the presigned URL if available, otherwise nil.
        def direct_download_url(expires_in = 15.minutes)
          return nil unless cloud_diskfile?
          
          case storage_backend
          when :s3
            s3_presigned_url(expires_in)
          when :gcs
            gcs_presigned_url(expires_in)
          when :azure
            azure_presigned_url(expires_in)
          else
            nil
          end
        end



        def files_to_final_location
          return unless @temp_file

          sha = Digest::SHA256.new
          content = read_temp_file(@temp_file, sha)
          self.disk_directory = target_directory

          upload_content(content)

          self.digest = sha.hexdigest
          @temp_file = nil

          set_content_type
        end

        def diskfile
          return local_diskfile unless cloud_diskfile?

          # Log usage for monitoring - this should be rarely called if direct downloads are working
          Rails.logger.info("[CloudAttachment] diskfile() called for cloud attachment #{self.id} - consider using direct_download_url() for better performance")

          # Use instance variable to cache the temp file path per request/instance
          return @cached_temp_diskfile if @cached_temp_diskfile && File.exist?(@cached_temp_diskfile)

          # Clean up any existing temp file first
          cleanup_temp_file

          @temp_file_obj = Tempfile.create(["redmine", File.extname(cloud_key)])
          @temp_file_obj.binmode
          begin
            download_from_cloud(@temp_file_obj)
            @temp_file_obj.rewind
            @cached_temp_diskfile = @temp_file_obj.path
          rescue => e
            Rails.logger.error("[CloudAttachment] Fallback to local for attachment #{self.id} due to cloud download error: #{e.message}")
            cleanup_temp_file
            return local_diskfile
          end

          @cached_temp_diskfile
        end

        def delete_from_cloud
          return unless cloud_diskfile?

          begin
            delete_from_backend(cloud_key)
          rescue => e
            Rails.logger.error("[CloudAttachment] Failed to delete #{cloud_key} from cloud for attachment #{self.id}: #{e.message}")
          end
        end

        # Override readable? method to optimize for cloud files
        def readable?
          return super unless cloud_diskfile?
          
          # For cloud files, check if disk_filename exists and cloud backend is configured
          return false unless disk_filename.present?
          
          case storage_backend
          when :s3
            cloud_config['bucket'].present? && cloud_config['access_key_id'].present?
          when :gcs
            cloud_config['bucket'].present? && cloud_config['project_id'].present?
          when :azure
            cloud_config['container'].present? && cloud_config['account_name'].present?
          else
            false
          end
        end

        # Override thumbnail method to optimize for cloud files
        def thumbnail(options={})
          if cloud_diskfile?
            # For cloud files, we need to download and generate thumbnail locally
            # But we'll cache it to avoid repeated downloads
            Rails.logger.debug("[CloudAttachment] Generating thumbnail for cloud attachment #{self.id}")
            
            if thumbnailable? && readable?
              size = options[:size].to_i
              if size > 0
                # Limit the number of thumbnails per image
                size = (size / 50.0).ceil * 50
                # Maximum thumbnail size
                size = 800 if size > 800
              else
                size = Setting.thumbnails_size.to_i
              end
              size = 100 unless size > 0
              target = thumbnail_path(size)

              # Check if thumbnail already exists
              return target if File.exist?(target)

              begin
                # Download cloud file to temp location for thumbnail generation
                source_file = diskfile # This will create temp file from cloud
                result = Redmine::Thumbnail.generate(source_file, target, size, is_pdf?)
                
                # Clean up temp file after thumbnail generation
                cleanup_after_thumbnail
                
                return result
              rescue => e
                # Clean up temp file even if generation fails
                cleanup_after_thumbnail
                
                if logger
                  logger.error(
                    "[CloudAttachment] An error occurred while generating thumbnail for cloud attachment #{self.id}: #{e.message}"
                  )
                end
                return nil
              end
            end
          else
            # Use original logic for local files
            super
          end
        end

        # Helper method to get expiry time from configuration
        def cloud_expiry_time
          plugin_cfg = Redmine::Configuration['cloud_attachment'] ||
                       Redmine::Configuration['cloud_attachment_pro']
          if plugin_cfg && plugin_cfg['presigned_url_expires_in']
            plugin_cfg['presigned_url_expires_in'].to_i.minutes
          else
            15.minutes
          end
        end

        # Check if attachment is stored in cloud
        def cloud_diskfile?
          disk_filename.to_s.match?(/^(s3|gcs|azure)_[^_]+_/)
        end

        # Get storage backend type based on configuration
        def storage_backend
          return @storage_backend if defined?(@storage_backend)
          
          @storage_backend = if cloud_diskfile?
            case disk_filename.to_s
            when /^s3_/
              :s3
            when /^gcs_/
              :gcs  
            when /^azure_/
              :azure
            else
              :local
            end
          else
            Redmine::Configuration["storage"]&.to_sym || :local
          end
        end

        private

        def upload_content(content)
          key = cloud_key

          case storage_backend
          when :s3
            s3_client.put_object(bucket: s3_bucket, key: key, body: content)
          when :gcs
            gcs_bucket.create_file(StringIO.new(content), key)
          when :azure
            azure_blob_client.create_block_blob(azure_container, key, content)
          else
            save_locally(content)
            return
          end

          self.disk_filename = "#{storage_backend}_#{File.basename(key)}"
        end

        def download_from_cloud(tmp)
          case storage_backend
          when :s3
            s3_client.get_object(bucket: s3_bucket, key: cloud_key) { |chunk| tmp.write(chunk) }
          when :gcs
            gcs_bucket.file(cloud_key)&.download(tmp.path)
          when :azure
            _, content = azure_blob_client.get_blob(azure_container, cloud_key)
            tmp.write(content)
          end
        end

        def delete_from_backend(key)
          case storage_backend
          when :s3
            s3_client.delete_object(bucket: s3_bucket, key: key)
          when :gcs
            gcs_bucket.file(key)&.delete
          when :azure
            azure_blob_client.delete_blob(azure_container, key)
          end
        end

        def save_locally(content)
          Attachment.create_diskfile(filename, disk_directory) do |f|
            self.disk_filename = File.basename(f.path)
            f.write(content)
          end
        end

        def set_content_type
          if content_type.blank? && filename.present?
            self.content_type = Redmine::MimeType.of(filename)
          end
          self.content_type = nil if content_type&.length.to_i > 255
        end

        def read_temp_file(temp_file, sha)
          content = temp_file.respond_to?(:read) ? temp_file.tap(&:rewind).read : temp_file.to_s
          sha.update(content)
          content
        end

        def cloud_filename
          disk_filename.presence || "#{SecureRandom.hex}_#{filename}"
        end

        def cloud_key
          prefix = "#{storage_backend}_"
          key = File.join(cloud_base_path, created_on.strftime('%Y/%m'), cloud_filename)
          cloud_diskfile? ? key.sub(/#{prefix}/, '') : key
        end

        def local_diskfile
          File.join(self.class.storage_path, disk_directory.to_s, disk_filename.to_s)
        end



        def cloud_config
          Redmine::Configuration[storage_backend.to_s] || {}
        end

        def cloud_base_path
          cloud_config['path'] || 'redmine/files'
        end

        def s3_client
          @s3_client ||= Aws::S3::Client.new(
            access_key_id: cloud_config['access_key_id'],
            secret_access_key: cloud_config['secret_access_key'],
            region: cloud_config['region']
          )
        end

        def s3_bucket
          cloud_config['bucket']
        end

        def gcs_client
          @gcs_client ||= Google::Cloud::Storage.new(
            project_id: cloud_config['project_id'],
            credentials: cloud_config['gcs_credentials']
          )
        end

        def gcs_bucket
          @gcs_bucket ||= gcs_client.bucket(cloud_config['bucket'])
        end

        def azure_blob_client
          @azure_blob_client ||= Azure::Storage::Blob::BlobService.create(
            storage_account_name: cloud_config['account_name'],
            storage_access_key: cloud_config['access_key']
          )
        end

        def azure_container
          cloud_config['container']
        end

        def s3_presigned_url(expires_in = 15.minutes)
          unless storage_backend == :s3 && cloud_config['bucket'].present?
            return nil
          end

          begin
            signer = Aws::S3::Presigner.new(client: s3_client)
            url = signer.presigned_url(:get_object, bucket: s3_bucket, key: cloud_key, expires_in: expires_in.to_i)
            Rails.logger.debug("[CloudAttachment] Generated S3 presigned URL for attachment #{self.id}")
            url
          rescue => e
            Rails.logger.error("[CloudAttachment] Failed to generate S3 presigned URL for #{cloud_key} (attachment #{self.id}): #{e.message}")
            nil
          end
        end

        def gcs_presigned_url(expires_in = 15.minutes)
          unless storage_backend == :gcs && cloud_config['bucket'].present?
            return nil
          end

          begin
            file = gcs_bucket.file(cloud_key)
            return nil unless file
            
            url = file.signed_url(method: "GET", expires: expires_in.to_i)
            Rails.logger.debug("[CloudAttachment] Generated GCS presigned URL for attachment #{self.id}")
            url
          rescue => e
            Rails.logger.error("[CloudAttachment] Failed to generate GCS presigned URL for #{cloud_key} (attachment #{self.id}): #{e.message}")
            nil
          end
        end

        def azure_presigned_url(expires_in = 15.minutes)
          unless storage_backend == :azure && cloud_config['container'].present?
            return nil
          end

          begin
            # Azure Blob Storage presigned URL (SAS token)
            start_time = Time.now.utc
            expiry_time = start_time + expires_in.to_i
            
            sas_token = azure_blob_client.generate_blob_sas_token(
              azure_container,
              cloud_key,
              permission: 'r', # Read permission
              start_time: start_time.iso8601,
              expiry_time: expiry_time.iso8601
            )
            
            url = azure_blob_client.generate_uri("#{azure_container}/#{cloud_key}") + "?#{sas_token}"
            Rails.logger.debug("[CloudAttachment] Generated Azure presigned URL for attachment #{self.id}")
            url
          rescue => e
            Rails.logger.error("[CloudAttachment] Failed to generate Azure presigned URL for #{cloud_key} (attachment #{self.id}): #{e.message}")
            nil
          end
        end

        # Clean up temporary file
        def cleanup_temp_file
          if @temp_file_obj && !@temp_file_obj.closed?
            @temp_file_obj.close
            @temp_file_obj.unlink rescue nil
          end
          @temp_file_obj = nil
          @cached_temp_diskfile = nil
        end

        # Clean up temp files after thumbnail generation
        def cleanup_after_thumbnail
          cleanup_temp_file
          Rails.logger.debug("[CloudAttachment] Cleaned up temp files after thumbnail generation for attachment #{self.id}")
        end
      end
    end
  end
end

# Ensure the patch is applied only once
Attachment.include RedmineCloudAttachment::AttachmentPatch unless Attachment.included_modules.include?(RedmineCloudAttachment::AttachmentPatch)

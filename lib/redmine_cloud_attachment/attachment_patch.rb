# frozen_string_literal: true

require_dependency 'attachment'

module RedmineCloudAttachment
  # Prepended onto Attachment so `super` reaches Redmine core methods.
  # Do NOT use include + class_eval to redefine methods — that breaks `super`.
  module AttachmentPatch
    def self.prepended(base)
      base.class_eval do
        after_destroy :delete_from_cloud
        before_destroy :cleanup_temp_file
      end
    end

    # Returns a time-limited direct URL for cloud-backed attachments, or nil.
    def direct_download_url(expires_in = 15.minutes)
      return nil unless cloud_diskfile?

      case storage_backend
      when :s3
        s3_presigned_url(expires_in)
      when :gcs
        gcs_presigned_url(expires_in)
      when :azure
        azure_presigned_url(expires_in)
      end
    end

    def files_to_final_location
      return super if configured_storage == :local
      return unless @temp_file

      sha = Digest::SHA256.new
      self.disk_directory = target_directory
      upload_and_digest(@temp_file, sha)
      self.digest = sha.hexdigest
      @temp_file = nil
      set_content_type
    end

    def diskfile
      return super unless cloud_diskfile?

      Rails.logger.info(
        "[CloudAttachment] diskfile() called for cloud attachment #{id} — prefer direct_download_url()"
      )

      return @cached_temp_diskfile if @cached_temp_diskfile && File.exist?(@cached_temp_diskfile)

      cleanup_temp_file

      @temp_file_obj = Tempfile.create(['redmine', File.extname(cloud_key.to_s)])
      @temp_file_obj.binmode
      begin
        download_from_cloud(@temp_file_obj)
        @temp_file_obj.rewind
        @cached_temp_diskfile = @temp_file_obj.path
      rescue StandardError => e
        Rails.logger.error(
          "[CloudAttachment] Fallback to local for attachment #{id} due to cloud download error: #{e.message}"
        )
        cleanup_temp_file
        return super
      end

      @cached_temp_diskfile
    end

    def delete_from_cloud
      return unless cloud_diskfile?

      delete_from_backend(cloud_key)
    rescue StandardError => e
      Rails.logger.error(
        "[CloudAttachment] Failed to delete #{cloud_key} from cloud for attachment #{id}: #{e.message}"
      )
    end

    def readable?
      return super unless cloud_diskfile?
      return false unless disk_filename.present?

      case storage_backend
      when :s3
        cloud_config['bucket'].present? &&
          (cloud_config['access_key_id'].present? || iam_role_credentials?)
      when :gcs
        cloud_config['bucket'].present? && cloud_config['project_id'].present?
      when :azure
        cloud_config['container'].present? && azure_account_name.present?
      else
        false
      end
    end

    def thumbnail(options = {})
      return super unless cloud_diskfile?

      Rails.logger.debug("[CloudAttachment] Generating thumbnail for cloud attachment #{id}")

      return unless thumbnailable? && readable?

      size = options[:size].to_i
      if size > 0
        size = (size / 50.0).ceil * 50
        size = 800 if size > 800
      else
        size = Setting.thumbnails_size.to_i
      end
      size = 100 unless size > 0
      target = thumbnail_path(size)
      return target if File.exist?(target)

      begin
        source_file = diskfile
        result = Redmine::Thumbnail.generate(source_file, target, size, is_pdf?)
        cleanup_after_thumbnail
        result
      rescue StandardError => e
        cleanup_after_thumbnail
        logger&.error(
          "[CloudAttachment] Thumbnail failed for cloud attachment #{id}: #{e.message}"
        )
        nil
      end
    end

    def cloud_expiry_time
      plugin_cfg = Redmine::Configuration['cloud_attachment'] ||
                   Redmine::Configuration['cloud_attachment_pro']
      if plugin_cfg && plugin_cfg['presigned_url_expires_in']
        plugin_cfg['presigned_url_expires_in'].to_i.minutes
      else
        15.minutes
      end
    end

    def cloud_diskfile?
      disk_filename.to_s.match?(/^(s3|gcs|azure)_/)
    end

    def storage_backend
      return @storage_backend if defined?(@storage_backend)

      @storage_backend =
        if cloud_diskfile?
          case disk_filename.to_s
          when /^s3_/ then :s3
          when /^gcs_/ then :gcs
          when /^azure_/ then :azure
          else :local
          end
        else
          configured_storage
        end
    end

    private

    def configured_storage
      Redmine::Configuration['storage']&.to_sym || :local
    end

    def upload_and_digest(temp_file, sha)
      path = materialize_upload_path(temp_file, sha)
      key = build_upload_key

      case storage_backend
      when :s3
        require_s3!
        File.open(path, 'rb') do |io|
          s3_client.put_object(bucket: s3_bucket, key: key, body: io)
        end
      when :gcs
        require_gcs!
        gcs_bucket.create_file(path, key)
      when :azure
        require_azure!
        File.open(path, 'rb') do |io|
          azure_blob_client.create_block_blob(azure_container, key, io)
        end
      else
        return
      end

      self.disk_filename = "#{storage_backend}_#{File.basename(key)}"
    end

    # Hash file in chunks and return a filesystem path suitable for SDK uploads.
    def materialize_upload_path(temp_file, sha)
      path =
        if temp_file.respond_to?(:path) && temp_file.path.present? && File.file?(temp_file.path)
          temp_file.path
        else
          tmp = Tempfile.new(['redmine-upload', File.extname(filename.to_s)])
          tmp.binmode
          data = temp_file.respond_to?(:read) ? temp_file.tap(&:rewind).read : temp_file.to_s
          tmp.write(data)
          tmp.flush
          tmp.close
          @upload_temp_to_unlink = tmp.path
          tmp.path
        end

      File.open(path, 'rb') do |io|
        while (chunk = io.read(1024 * 1024))
          sha.update(chunk)
        end
      end

      path
    end

    def build_upload_key
      stamp = (created_on || Time.current).strftime('%Y/%m')
      base = disk_filename.presence || "#{SecureRandom.hex}_#{filename}"
      File.join(cloud_base_path, stamp, base)
    end

    def download_from_cloud(tmp)
      case storage_backend
      when :s3
        require_s3!
        s3_client.get_object(bucket: s3_bucket, key: cloud_key) { |chunk| tmp.write(chunk) }
      when :gcs
        require_gcs!
        gcs_bucket.file(cloud_key)&.download(tmp.path)
      when :azure
        require_azure!
        _props, content = azure_blob_client.get_blob(azure_container, cloud_key)
        tmp.write(content)
      end
    end

    def delete_from_backend(key)
      case storage_backend
      when :s3
        require_s3!
        s3_client.delete_object(bucket: s3_bucket, key: key)
      when :gcs
        require_gcs!
        gcs_bucket.file(key)&.delete
      when :azure
        require_azure!
        azure_blob_client.delete_blob(azure_container, key)
      end
    end

    def set_content_type
      if content_type.blank? && filename.present?
        self.content_type = Redmine::MimeType.of(filename)
      end
      self.content_type = nil if content_type&.length.to_i > 255
    end

    def cloud_filename
      disk_filename.presence || "#{SecureRandom.hex}_#{filename}"
    end

    def cloud_key
      prefix = "#{storage_backend}_"
      key = File.join(
        cloud_base_path,
        (created_on || Time.current).strftime('%Y/%m'),
        cloud_filename
      )
      cloud_diskfile? ? key.sub(prefix, '') : key
    end

    def cloud_config
      Redmine::Configuration[storage_backend.to_s] || {}
    end

    def cloud_base_path
      cloud_config['path'] || 'redmine/files'
    end

    def iam_role_credentials?
      # Allow EC2/ECS instance profiles when explicit keys are omitted.
      cloud_config['access_key_id'].blank? && cloud_config['secret_access_key'].blank?
    end

    # Accept both sample keys (storage_account_name) and legacy short keys (account_name).
    def azure_account_name
      cloud_config['account_name'].presence || cloud_config['storage_account_name']
    end

    def azure_access_key
      cloud_config['access_key'].presence || cloud_config['storage_access_key']
    end

    def require_s3!
      require 'aws-sdk-s3'
    end

    def require_gcs!
      require 'google/cloud/storage'
    end

    def require_azure!
      require 'azure/storage/blob'
    end

    def s3_client
      require_s3!
      @s3_client ||= begin
        opts = { region: cloud_config['region'] }
        if cloud_config['access_key_id'].present?
          opts[:access_key_id] = cloud_config['access_key_id']
          opts[:secret_access_key] = cloud_config['secret_access_key']
        end
        Aws::S3::Client.new(opts)
      end
    end

    def s3_bucket
      cloud_config['bucket']
    end

    def gcs_client
      require_gcs!
      @gcs_client ||= Google::Cloud::Storage.new(
        project_id: cloud_config['project_id'],
        credentials: cloud_config['gcs_credentials']
      )
    end

    def gcs_bucket
      @gcs_bucket ||= gcs_client.bucket(cloud_config['bucket'])
    end

    def azure_blob_client
      require_azure!
      @azure_blob_client ||= Azure::Storage::Blob::BlobService.create(
        storage_account_name: azure_account_name,
        storage_access_key: azure_access_key
      )
    end

    def azure_container
      cloud_config['container']
    end

    def s3_presigned_url(expires_in = 15.minutes)
      return nil unless storage_backend == :s3 && cloud_config['bucket'].present?

      require_s3!
      signer = Aws::S3::Presigner.new(client: s3_client)
      signer.presigned_url(
        :get_object,
        bucket: s3_bucket,
        key: cloud_key,
        expires_in: expires_in.to_i
      )
    rescue StandardError => e
      Rails.logger.error(
        "[CloudAttachment] Failed to generate S3 presigned URL for #{cloud_key} (attachment #{id}): #{e.message}"
      )
      nil
    end

    def gcs_presigned_url(expires_in = 15.minutes)
      return nil unless storage_backend == :gcs && cloud_config['bucket'].present?

      require_gcs!
      file = gcs_bucket.file(cloud_key)
      return nil unless file

      file.signed_url(method: 'GET', expires: expires_in.to_i)
    rescue StandardError => e
      Rails.logger.error(
        "[CloudAttachment] Failed to generate GCS presigned URL for #{cloud_key} (attachment #{id}): #{e.message}"
      )
      nil
    end

    def azure_presigned_url(expires_in = 15.minutes)
      return nil unless storage_backend == :azure && cloud_config['container'].present?

      require_azure!
      start_time = Time.now.utc
      expiry_time = start_time + expires_in.to_i

      sas_token = azure_blob_client.generate_blob_sas_token(
        azure_container,
        cloud_key,
        permission: 'r',
        start_time: start_time.iso8601,
        expiry_time: expiry_time.iso8601
      )

      "#{azure_blob_client.generate_uri("#{azure_container}/#{cloud_key}")}?#{sas_token}"
    rescue StandardError => e
      Rails.logger.error(
        "[CloudAttachment] Failed to generate Azure presigned URL for #{cloud_key} (attachment #{id}): #{e.message}"
      )
      nil
    end

    def cleanup_temp_file
      if @temp_file_obj && !@temp_file_obj.closed?
        @temp_file_obj.close
        begin
          @temp_file_obj.unlink
        rescue StandardError
          nil
        end
      end
      @temp_file_obj = nil
      @cached_temp_diskfile = nil
      if @upload_temp_to_unlink && File.exist?(@upload_temp_to_unlink)
        begin
          File.unlink(@upload_temp_to_unlink)
        rescue StandardError
          nil
        end
      end
      @upload_temp_to_unlink = nil
    end

    def cleanup_after_thumbnail
      cleanup_temp_file
      Rails.logger.debug("[CloudAttachment] Cleaned up temp files after thumbnail for attachment #{id}")
    end
  end
end

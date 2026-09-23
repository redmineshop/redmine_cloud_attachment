# frozen_string_literal: true

require 'uri'

module RedmineCloudAttachment
  # Pure helpers for object keys, presigned URL hosts, and log redaction.
  # No Rails dependency so the checks can run under MiniTest without a Redmine boot.
  module StorageSecurity
    class ConfigurationError < StandardError; end

    MAX_EXPIRY_MINUTES = 7 * 24 * 60
    MAX_EXPIRY_SECONDS = MAX_EXPIRY_MINUTES * 60
    S3_REGION = /\A[a-z0-9-]{1,32}\z/
    CONTROL_CHARS = /[\x00-\x1f\x7f]/

    module_function

    def expiry_minutes(raw)
      minutes = raw.nil? || raw.to_s.strip.empty? ? 15 : raw.to_i
      minutes.clamp(1, MAX_EXPIRY_MINUTES)
    end

    def expiry_seconds(value)
      seconds = value.nil? ? 15 * 60 : value.to_i
      seconds.clamp(60, MAX_EXPIRY_SECONDS)
    end

    def thumbnail_pixel_size(requested, default_size)
      number =
        if requested.is_a?(Numeric) || requested.is_a?(String)
          requested.to_i
        else
          0
        end

      if number.positive?
        number = (number / 50.0).ceil * 50
        number = 800 if number > 800
      else
        number = default_size.to_i
      end

      number.positive? ? number : 100
    end

    def safe_temp_suffix(filename)
      ext = File.extname(filename.to_s)
      ext.match?(/\A\.[A-Za-z0-9]{1,8}\z/) ? ext : ''
    end

    # Blank is valid (real AWS, no custom endpoint). Reject userinfo so secrets
    # are not embedded in the URL the SDK may log.
    def valid_http_endpoint?(value)
      text = value.to_s.strip
      return true if text.empty?

      uri = URI.parse(text)
      return false unless uri.is_a?(URI::HTTP)
      return false if uri.host.nil? || uri.host.empty?
      return false unless uri.userinfo.nil?
      return false if uri.host.match?(CONTROL_CHARS) || uri.host.include?('\\')

      true
    rescue URI::InvalidURIError
      false
    end

    def safe_container_name?(name)
      value = name.to_s
      return false if value.empty? || value.length > 255
      return false if value.include?('..') || value.include?('/') || value.include?('\\')
      return false if value.match?(/[\s?#]/) || value.match?(CONTROL_CHARS)

      true
    end

    def s3_credentials_ok?(config)
      cfg = stringify_config(config)
      access_key = cfg['access_key_id'].to_s.strip
      secret = cfg['secret_access_key'].to_s.strip
      return true if access_key.empty? && secret.empty?

      !access_key.empty? && !secret.empty?
    end

    def azure_credentials_ok?(config)
      cfg = stringify_config(config)
      account = azure_account_name(cfg)
      key = cfg['access_key'].to_s.strip
      key = cfg['storage_access_key'].to_s.strip if key.empty?
      return false if account.empty? || key.empty?

      account.match?(/\A[a-z0-9]{3,24}\z/i)
    end

    def azure_account_name(config)
      cfg = stringify_config(config)
      name = cfg['account_name'].to_s.strip
      name = cfg['storage_account_name'].to_s.strip if name.empty?
      name
    end

    def object_key(base_path:, stamp:, disk_filename:, backend:, strip_prefix:)
      name = object_basename(disk_filename, backend: backend, strip_prefix: strip_prefix)
      return nil if name.nil?

      prefix = normalized_prefix(base_path)
      date_path = stamp.to_s
      return nil unless date_path.match?(/\A\d{4}\/\d{2}\z/)

      [prefix, date_path, name].reject(&:empty?).join('/')
    end

    def object_basename(disk_filename, backend:, strip_prefix:)
      name = disk_filename.to_s.gsub('\\', '/')
      if strip_prefix && backend && !backend.to_s.empty?
        prefix = "#{backend}_"
        name = name.delete_prefix(prefix) if name.start_with?(prefix)
      end
      name = File.basename(name)
      return nil if name.empty? || name == '.' || name == '..'
      return nil if name.match?(CONTROL_CHARS) || name.match?(/[?#\\"'<>]/)

      name
    end

    def normalized_prefix(path)
      path.to_s.gsub('\\', '/').split('/').reject { |segment| segment.empty? || segment == '.' || segment == '..' }.join('/')
    end

    def presign_origins(backend, config)
      cfg = stringify_config(config)
      case backend.to_sym
      when :s3
        s3_origins(cfg)
      when :gcs
        gcs_origins(cfg)
      when :azure
        azure_origins(cfg)
      else
        []
      end
    end

    def presigned_url_allowed?(url, origins, bucket:)
      return false unless url.is_a?(String)
      return false if url.match?(CONTROL_CHARS)

      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP)
      return false unless uri.userinfo.nil?
      return false if uri.host.nil? || uri.host.empty?
      return false if uri.host.match?(/[\s%\\@]/) || uri.host.match?(CONTROL_CHARS)
      return false unless Array(origins).include?(origin_key(uri))
      return false unless safe_url_path?(uri.path)

      bucket_matches?(uri, bucket)
    rescue URI::InvalidURIError
      false
    end

    def sanitize_log_text(text)
      cleaned = text.to_s.gsub(CONTROL_CHARS, ' ')
      cleaned = cleaned.gsub(%r{(https?://)[^\s/@]+:[^\s/@]+@}i, '\1[redacted]@')
      cleaned = cleaned.gsub(%r{https?://[^\s?]+(?:\?[^\s]*)?}i) do |match|
        match.sub(/\?.*/, '?[redacted]')
      end
      cleaned = cleaned.gsub(
        /(secret[_\s-]*access[_\s-]*key|storage[_\s-]*access[_\s-]*key|aws_secret_access_key)(\s*[=:]\s*['"]?)\S+/i,
        '\1\2[redacted]'
      )
      cleaned = cleaned.gsub(/\bAKIA[0-9A-Z]{16}\b/, '[redacted]')
      cleaned.length > 300 ? "#{cleaned[0, 300]}…" : cleaned
    end

    def s3_origins(config)
      public_endpoint = config['public_endpoint'].to_s.strip
      endpoint = config['endpoint'].to_s.strip
      if !public_endpoint.empty?
        return endpoint_origins(public_endpoint)
      end
      return endpoint_origins(endpoint) unless endpoint.empty?

      aws_default_origins(config)
    end

    def gcs_origins(_config)
      ['https://storage.googleapis.com:443']
    end

    def azure_origins(config)
      account = azure_account_name(config).downcase
      return [] unless account.match?(/\A[a-z0-9]{3,24}\z/)

      ["https://#{account}.blob.core.windows.net:443"]
    end

    def endpoint_origins(value)
      return [] unless valid_http_endpoint?(value)

      uri = URI.parse(value.to_s.strip)
      [origin_key(uri)]
    rescue URI::InvalidURIError
      []
    end

    def aws_default_origins(config)
      bucket = config['bucket'].to_s
      region = config['region'].to_s.strip
      region = 'us-east-1' if region.empty?
      return [] unless region.match?(S3_REGION)
      return [] unless safe_container_name?(bucket)

      hosts = [
        "#{bucket}.s3.#{region}.amazonaws.com",
        "#{bucket}.s3.dualstack.#{region}.amazonaws.com",
        "s3.#{region}.amazonaws.com"
      ]
      if region == 'us-east-1'
        hosts << "#{bucket}.s3.amazonaws.com"
        hosts << 's3.amazonaws.com'
      end
      hosts.map { |host| "https://#{host}:443" }
    end

    def origin_key(uri)
      "#{uri.scheme.downcase}://#{uri.host.downcase}:#{uri.port}"
    end

    def safe_url_path?(path)
      segments = path.to_s.split('/')
      segments.none? { |segment| segment == '.' || segment == '..' }
    end

    def bucket_matches?(uri, bucket)
      name = bucket.to_s
      return false unless safe_container_name?(name)

      host = uri.host.downcase
      virtual = host == "#{name.downcase}.s3.amazonaws.com" || host.start_with?("#{name.downcase}.s3.")
      return true if virtual

      path = uri.path.to_s
      path == "/#{name}" || path.start_with?("/#{name}/")
    end

    def stringify_config(config)
      return {} if config.nil?

      config.each_with_object({}) do |(key, value), out|
        out[key.to_s] = value
      end
    end
  end
end

# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'aws-sdk-s3'
require 'digest'
require 'net/http'

class MinioStorageTest < Redmine::IntegrationTest
  def setup
    super
    clear_cloud_attachment_stubs
    if ENV['MINIO_ENDPOINT'].to_s.empty?
      skip 'MINIO_ENDPOINT is not set, so live S3 tests are not run'
    end
    ensure_bucket
  end

  def teardown
    if @uploaded_key && ENV['MINIO_ENDPOINT'].present?
      minio_client.delete_object(bucket: bucket_name, key: @uploaded_key)
    end
  rescue StandardError
    nil
  ensure
    clear_cloud_attachment_stubs
    super
  end

  def test_upload_download_and_delete_round_trip
    attachment = nil
    with_minio_config do
      attachment = save_cloud_file('hello cloud')
      @uploaded_key = attachment.send(:cloud_key)
      local = File.join(Attachment.storage_path, attachment.disk_directory.to_s, attachment.disk_filename.to_s)

      assert attachment.disk_filename.start_with?('s3_')
      assert_not File.exist?(local)
      assert_equal Digest::SHA256.hexdigest('hello cloud'), attachment.digest
      assert_equal 'hello cloud', minio_client.get_object(bucket: bucket_name, key: @uploaded_key).body.read

      log_user('jsmith', 'jsmith')
      logged = capture_log do
        get "/attachments/download/#{attachment.id}/#{attachment.filename}"
      end

      assert_response :redirect
      location = response.location.to_s
      assert_includes location, endpoint_host
      refute_includes location, 'evil.example'
      uri = URI(location)
      expires = URI.decode_www_form(uri.query.to_s).to_h['X-Amz-Expires'].to_i
      assert_equal 900, expires
      signature = URI.decode_www_form(uri.query.to_s).to_h['X-Amz-Signature'].to_s
      refute_includes logged, signature if signature.present?
      refute_includes logged, 'secret_access_key'

      fetched = Net::HTTP.get_response(uri)
      assert_equal '200', fetched.code
      assert_equal 'hello cloud', fetched.body

      attachment.destroy
      assert_raises(Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound) do
        minio_client.get_object(bucket: bucket_name, key: @uploaded_key)
      end
      @uploaded_key = nil
    end
  end

  def test_presigned_expiry_is_clamped_to_seven_days
    with_minio_config(expires_minutes: 999_999) do
      attachment = save_cloud_file('expiry')
      @uploaded_key = attachment.send(:cloud_key)
      log_user('jsmith', 'jsmith')

      get "/attachments/download/#{attachment.id}/#{attachment.filename}"

      assert_response :redirect
      expires = URI.decode_www_form(URI(response.location).query.to_s).to_h['X-Amz-Expires'].to_i
      assert_equal 7 * 24 * 60 * 60, expires
    end
  end

  def test_user_without_issue_visibility_does_not_receive_a_presigned_url
    with_minio_config do
      attachment = save_cloud_file('private-bytes')
      @uploaded_key = attachment.send(:cloud_key)
      Issue.where(id: attachment.container_id).update_all(is_private: true, assigned_to_id: nil)
      log_user('someone', 'foo')

      get "/attachments/download/#{attachment.id}/#{attachment.filename}"

      assert_response :forbidden
      refute_includes response.location.to_s, 'X-Amz-'
      refute_includes response.body.to_s, 'X-Amz-'
      refute_includes response.body.to_s, 'private-bytes'
    end
  end

  private

  def bucket_name
    ENV.fetch('MINIO_BUCKET', 'redmine-attachments')
  end

  def endpoint_host
    URI(ENV.fetch('MINIO_ENDPOINT')).host
  end

  def minio_client
    @minio_client ||= Aws::S3::Client.new(
      access_key_id: ENV.fetch('MINIO_ACCESS_KEY_ID', 'minioadmin'),
      secret_access_key: ENV.fetch('MINIO_SECRET_ACCESS_KEY', 'minioadmin'),
      region: 'us-east-1',
      endpoint: ENV.fetch('MINIO_ENDPOINT'),
      force_path_style: true
    )
  end

  def ensure_bucket
    minio_client.create_bucket(bucket: bucket_name)
  rescue Aws::S3::Errors::BucketAlreadyOwnedByYou, Aws::S3::Errors::BucketAlreadyExists
    nil
  end

  def with_minio_config(expires_minutes: 15)
    endpoint = ENV.fetch('MINIO_ENDPOINT')
    with_redmine_config(
      'storage' => 's3',
      's3' => {
        'bucket' => bucket_name,
        'region' => 'us-east-1',
        'path' => 'redmine/files',
        'access_key_id' => ENV.fetch('MINIO_ACCESS_KEY_ID', 'minioadmin'),
        'secret_access_key' => ENV.fetch('MINIO_SECRET_ACCESS_KEY', 'minioadmin'),
        'endpoint' => endpoint,
        'public_endpoint' => endpoint,
        'force_path_style' => true
      },
      'cloud_attachment' => { 'presigned_url_expires_in' => expires_minutes }
    ) do
      yield
    end
  end

  def save_cloud_file(contents)
    file = Tempfile.new(['minio', '.txt'])
    file.binmode
    file.write(contents)
    file.rewind
    attachment = Attachment.new(author: User.find(2), container: Issue.find(1))
    attachment.created_on = Time.utc(2026, 9, 24, 12, 0, 0)
    attachment.filename = "notes-#{SecureRandom.hex(4)}.txt"
    attachment.file = file
    attachment.save!
    attachment
  end

  def capture_log
    io = StringIO.new
    previous = Rails.logger
    Rails.logger = Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = previous if previous
  end
end

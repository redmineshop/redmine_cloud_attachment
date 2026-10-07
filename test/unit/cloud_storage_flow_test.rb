# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)
require 'digest'

class FakeS3Client
  attr_reader :puts, :deletes, :gets

  def initialize
    @objects = {}
    @puts = []
    @deletes = []
    @gets = []
    @error = nil
  end

  def fail_next_get!(message)
    @error = message
  end

  def put_object(bucket:, key:, body:)
    data = body.respond_to?(:read) ? body.read : body.to_s
    @objects[[bucket, key]] = data
    @puts << { bucket: bucket, key: key, body: data }
  end

  def get_object(bucket:, key:)
    @gets << { bucket: bucket, key: key }
    raise StandardError, @error if @error

    data = @objects[[bucket, key]]
    raise StandardError, 'missing object' if data.nil?

    yield data if block_given?
    data
  end

  def delete_object(bucket:, key:)
    @deletes << { bucket: bucket, key: key }
    @objects.delete([bucket, key])
  end
end

class CloudStorageFlowTest < ActiveSupport::TestCase
  S3_CONFIG = {
    'bucket' => 'redmine-attachments',
    'region' => 'us-east-1',
    'path' => 'redmine/files',
    'access_key_id' => 'minioadmin',
    'secret_access_key' => 'minioadmin',
    'endpoint' => 'http://127.0.0.1:9000',
    'public_endpoint' => 'http://127.0.0.1:9000',
    'force_path_style' => true
  }.freeze

  def test_upload_stores_bytes_on_the_s3_client_and_not_on_local_disk
    client = FakeS3Client.new
    attachment = nil
    with_tmp_attachments_directory do
      with_redmine_config('storage' => 's3', 's3' => S3_CONFIG) do
        attachment = build_upload('hello cloud', 'notes.txt')
        attach_client(attachment, client)
        attachment.save!

        local = File.join(Attachment.storage_path, attachment.disk_directory.to_s, attachment.disk_filename.to_s)
        assert attachment.disk_filename.start_with?('s3_'), attachment.disk_filename
        assert_not File.exist?(local)
        assert_equal ['hello cloud'], client.puts.map { |row| row[:body] }
        assert_equal Digest::SHA256.hexdigest('hello cloud'), attachment.digest
        attachment.remove_instance_variable(:@storage_backend) if attachment.instance_variable_defined?(:@storage_backend)
        assert_equal client.puts.first[:key], attachment.send(:cloud_key)
        refute_includes client.puts.first[:key], '..'

        assert_equal 'hello cloud', File.binread(attachment.diskfile)
        gets_after_read = client.gets.size
        attachment.send(:reuse_existing_file_if_possible)
        attachment.send(:delete_from_disk!)
        assert_equal gets_after_read, client.gets.size

        key = client.puts.first[:key]
        attachment.destroy
        assert_equal [key], client.deletes.map { |row| row[:key] }
      end
    end
  end

  def test_upload_key_drops_a_traversal_filename
    client = FakeS3Client.new
    with_tmp_attachments_directory do
      with_redmine_config('storage' => 's3', 's3' => S3_CONFIG) do
        attachment = build_upload('hello cloud', '../../etc/passwd.txt')
        attach_client(attachment, client)
        attachment.save!
        refute_includes client.puts.first[:key], '..'
        assert_match %r{\Aredmine/files/2026/09/[0-9a-f]+\.txt\z}, client.puts.first[:key]
      end
    end
  end

  def test_failed_cloud_read_does_not_return_the_local_path_or_log_secrets
    client = FakeS3Client.new
    client.fail_next_get!('secret_access_key=supersecret https://127.0.0.1:9000/k?X-Amz-Signature=abcdef1234567890')
    attachment = nil
    with_tmp_attachments_directory do
      with_redmine_config('storage' => 's3', 's3' => S3_CONFIG) do
        attachment = build_upload('hello cloud', 'notes.txt')
        attach_client(attachment, client)
        attachment.save!
      end
      local = File.join(Attachment.storage_path, attachment.disk_directory.to_s, attachment.disk_filename.to_s)
      io = StringIO.new
      previous = Rails.logger
      Rails.logger = Logger.new(io)
      assert_nil attachment.diskfile
      refute_equal local, attachment.diskfile
      logged = io.string
      refute_includes logged, 'supersecret'
      refute_includes logged, 'abcdef1234567890'
      assert_includes logged, '[redacted]'
    ensure
      Rails.logger = previous if previous
    end
  end

  def test_local_storage_still_writes_a_disk_file
    attachment = nil
    with_tmp_attachments_directory do
      with_redmine_config('storage' => 'local') do
        attachment = build_upload('local-bytes', 'local.txt')
        attachment.save!
        assert_not attachment.cloud_diskfile?
        assert_equal 'local-bytes', File.binread(attachment.diskfile)
      end
    ensure
      if attachment&.disk_filename.present? && !attachment.cloud_diskfile?
        path = File.join(Attachment.storage_path, attachment.disk_directory.to_s, attachment.disk_filename.to_s)
        FileUtils.rm_f(path)
      end
    end
  end

  private

  def attach_client(attachment, client)
    attachment.define_singleton_method(:require_s3!) {}
    attachment.define_singleton_method(:s3_client) { client }
  end

  def build_upload(contents, filename)
    file = Tempfile.new(['upload', File.extname(filename)])
    file.binmode
    file.write(contents)
    file.rewind
    attachment = Attachment.new(author: User.find(2), container: Issue.find(1))
    attachment.created_on = Time.utc(2026, 9, 24, 12, 0, 0)
    attachment.filename = filename
    attachment.file = file
    attachment
  end
end

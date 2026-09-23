# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# Overrides used only while this file's examples run. Unset thread locals
# delegate to the real cloud attachment methods.
module CloudAttachmentDownloadSecurityStub
  def direct_download_url(*)
    return Thread.current[:rca_direct_url] if Thread.current[:rca_stub_url]

    super
  end

  def cloud_config
    Thread.current[:rca_cloud_config] || super
  end

  def diskfile
    return Thread.current[:rca_diskfile] if Thread.current[:rca_diskfile]

    super
  end
end

class AttachmentsDownloadSecurityTest < Redmine::ControllerTest
  fixtures :projects, :users, :roles, :members, :member_roles, :issues,
           :trackers, :issue_statuses, :enabled_modules, :enumerations, :attachments

  MINIO_CONFIG = {
    'bucket' => 'redmine-attachments',
    'region' => 'us-east-1',
    'path' => 'redmine/files',
    'access_key_id' => 'minioadmin',
    'secret_access_key' => 'minioadmin',
    'endpoint' => 'http://demo-minio:9000',
    'public_endpoint' => 'http://localhost:9000',
    'force_path_style' => true
  }.freeze

  def setup
    Attachment.prepend(CloudAttachmentDownloadSecurityStub) unless Attachment.ancestors.include?(CloudAttachmentDownloadSecurityStub)
    @attachment = Attachment.find(1)
    @attachment.update_columns(
      disk_filename: 's3_notes.txt',
      filename: 'notes.txt',
      content_type: 'text/plain',
      filesize: 5
    )
    @request.session[:user_id] = 2
    Thread.current[:rca_cloud_config] = MINIO_CONFIG
  end

  def teardown
    Thread.current[:rca_stub_url] = nil
    Thread.current[:rca_direct_url] = nil
    Thread.current[:rca_cloud_config] = nil
    Thread.current[:rca_diskfile] = nil
  end

  def test_download_redirects_to_the_configured_storage_host
    url = 'http://localhost:9000/redmine-attachments/redmine/files/2026/09/notes.txt?X-Amz-Signature=sekret'
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = url

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    assert_response :redirect
    assert_equal url, response.location
    refute_match(/evil\.example/, response.location.to_s)
  end

  def test_download_does_not_redirect_to_an_off_host_presign
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'https://evil.example/redmine-attachments/secret?X-Amz-Signature=sekret'
    file = Tempfile.new('cloud-local')
    file.write('hello')
    file.close
    Thread.current[:rca_diskfile] = file.path

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    refute_includes response.location.to_s, 'evil.example'
    refute_includes response.body.to_s, 'evil.example'
  ensure
    file&.close
    file&.unlink
  end

  def test_image_show_does_not_embed_an_off_host_url
    @attachment.update_columns(
      disk_filename: 's3_notes.jpg',
      filename: 'notes.jpg',
      content_type: 'image/jpeg'
    )
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'https://evil.example/redmine-attachments/notes.jpg?X-Amz-Signature=sekret'

    get :show, params: { id: @attachment.id }

    assert_response :success
    refute_includes response.body, 'evil.example'
  end

  def test_anonymous_cannot_receive_a_presigned_url
    project = @attachment.container.respond_to?(:project) ? @attachment.container.project : Project.find(1)
    project.update!(is_public: false)
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'http://localhost:9000/redmine-attachments/secret?X-Amz-Signature=sekret'
    @request.session[:user_id] = nil

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    refute_includes response.location.to_s, 'X-Amz-Signature'
    refute_includes response.location.to_s, 'localhost:9000'
    refute_includes response.body.to_s, 'X-Amz-Signature'
  end
end

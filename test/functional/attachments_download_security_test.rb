# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class AttachmentsDownloadSecurityTest < Redmine::ControllerTest
  tests AttachmentsController

  fixtures :projects, :users, :roles, :members, :member_roles, :issues,
           :trackers, :issue_statuses, :enabled_modules, :enumerations, :attachments

  MINIO_CONFIG = {
    'bucket' => 'redmine-attachments',
    'region' => 'us-east-1',
    'path' => 'redmine/files',
    'access_key_id' => 'minioadmin',
    'secret_access_key' => 'minioadmin',
    'endpoint' => 'http://127.0.0.1:9000',
    'public_endpoint' => 'http://127.0.0.1:9000',
    'force_path_style' => true
  }.freeze

  def setup
    super
    @attachment = Attachment.find(1)
    @attachment.update_columns(
      disk_filename: 's3_notes.txt',
      filename: 'notes.txt',
      content_type: 'text/plain',
      filesize: 5
    )
    @request.session[:user_id] = 2
    Thread.current[:rca_stub_config] = true
    Thread.current[:rca_cloud_config] = MINIO_CONFIG
  end

  def teardown
    clear_cloud_attachment_stubs
    super
  end

  def test_download_redirects_to_the_configured_storage_host
    url = 'http://127.0.0.1:9000/redmine-attachments/redmine/files/2026/09/notes.txt?X-Amz-Signature=sekret'
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = url
    logged = capture_log do
      get :download, params: { id: @attachment.id, filename: @attachment.filename }
    end

    assert_response :redirect
    assert_equal url, response.location
    refute_includes logged, 'X-Amz-Signature=sekret'
    refute_includes logged, 'minioadmin'
  end

  def test_download_does_not_redirect_to_an_off_host_presign
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'https://evil.example/redmine-attachments/secret?X-Amz-Signature=sekret'
    file = Tempfile.new('cloud-local')
    file.write('hello-from-redmine')
    file.close
    Thread.current[:rca_stub_diskfile] = true
    Thread.current[:rca_diskfile] = file.path

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    assert_response :success
    assert_includes response.body, 'hello-from-redmine'
    refute_includes response.location.to_s, 'evil.example'
    refute_includes response.body.to_s, 'evil.example'
  ensure
    file&.close
    file&.unlink
  end

  def test_missing_cloud_object_is_not_found
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'https://evil.example/redmine-attachments/secret?X-Amz-Signature=sekret'
    Thread.current[:rca_stub_diskfile] = true
    Thread.current[:rca_diskfile] = nil

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    assert_response :not_found
    refute_includes response.location.to_s, 'evil.example'
    refute_includes response.body.to_s, 'X-Amz-Signature'
  end

  def test_download_rejects_a_mismatched_filename
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'http://127.0.0.1:9000/redmine-attachments/notes.txt?X-Amz-Signature=sekret'

    get :download, params: { id: @attachment.id, filename: 'other.txt' }

    assert_response :not_found
    refute_includes response.location.to_s, '127.0.0.1:9000'
    refute_includes response.body.to_s, 'X-Amz-Signature'
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

  def test_cloud_pdf_uses_the_pdf_preview
    @attachment.update_columns(
      disk_filename: 's3_notes.pdf',
      filename: 'notes.pdf',
      content_type: 'application/pdf',
      filesize: 10
    )

    get :show, params: { id: @attachment.id }

    assert_response :success
    assert_includes response.body, 'filecontent pdf'
  end

  def test_cloud_text_preview_reads_the_downloaded_tempfile
    file = Tempfile.new('cloud-text')
    file.write('cloud-text-body')
    file.close
    Thread.current[:rca_stub_diskfile] = true
    Thread.current[:rca_diskfile] = file.path
    @attachment.update_columns(filesize: 15)

    get :show, params: { id: @attachment.id }

    assert_response :success
    assert_includes response.body, 'cloud-text-body'
  ensure
    file&.close
    file&.unlink
  end

  def test_anonymous_cannot_receive_a_presigned_url
    project = @attachment.container.project
    project.update!(is_public: false)
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'http://127.0.0.1:9000/redmine-attachments/secret?X-Amz-Signature=sekret'
    @request.session[:user_id] = nil

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    refute_includes response.location.to_s, 'X-Amz-Signature'
    refute_includes response.location.to_s, '127.0.0.1:9000'
    refute_includes response.body.to_s, 'X-Amz-Signature'
  end

  def test_user_who_cannot_see_a_private_issue_gets_no_presigned_url
    Issue.where(id: @attachment.container_id).update_all(is_private: true, assigned_to_id: nil)
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = 'http://127.0.0.1:9000/redmine-attachments/secret?X-Amz-Signature=sekret'
    @request.session[:user_id] = 7

    get :download, params: { id: @attachment.id, filename: @attachment.filename }

    assert_response :forbidden
    refute_includes response.location.to_s, 'X-Amz-Signature'
    refute_includes response.body.to_s, 'X-Amz-Signature'
    refute_includes response.body.to_s, 'cloud-bulk-secret'
  end

  def test_bulk_download_requires_attachment_visibility
    file = Tempfile.new('bulk-secret')
    file.write('cloud-bulk-secret')
    file.close
    Thread.current[:rca_stub_diskfile] = true
    Thread.current[:rca_diskfile] = file.path
    Attachment.create!(
      container: Project.find(1),
      author_id: 2,
      filename: 'secret.txt',
      disk_filename: 's3_secret.txt',
      disk_directory: '2026/09',
      filesize: 17,
      content_type: 'text/plain',
      digest: 'ab' * 32
    )
    role = Role.non_member
    role.remove_permission!(:view_files)
    @request.session[:user_id] = 7

    get :download_all, params: { object_type: 'projects', object_id: Project.find(1).id }

    assert_response :forbidden
    refute_includes response.body.to_s, 'cloud-bulk-secret'
  ensure
    role&.add_permission!(:view_files)
    file&.close
    file&.unlink
  end

  def test_bulk_download_size_error_ignores_an_external_referer
    with_tmp_attachments_directory do
      source = Tempfile.new(['project-file', '.txt'])
      source.write('project-file-bytes')
      source.rewind
      attachment = Attachment.new(author: User.find(2), container: Project.find(1))
      attachment.filename = 'project-file.txt'
      attachment.file = source
      attachment.save!
      @request.env['HTTP_REFERER'] = 'https://evil.example/phish'
      with_settings bulk_download_max_size: 0 do
        get :download_all, params: { object_type: 'projects', object_id: 1 }
      end

      assert_response :redirect
      assert_match %r{/projects/ecookbook/files}, response.location.to_s
      refute_includes response.location.to_s, 'evil.example'
    end
  end

  private

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

# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class CloudAttachmentIntegrationTest < Redmine::IntegrationTest
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

  def teardown
    clear_cloud_attachment_stubs
    super
  end

  def test_download_route_redirects_for_a_visible_cloud_attachment
    attachment = cloud_fixture
    url = 'http://127.0.0.1:9000/redmine-attachments/redmine/files/2026/09/notes.txt?X-Amz-Signature=sekret'
    stub_direct_url(url)
    log_user('jsmith', 'jsmith')

    get "/attachments/download/#{attachment.id}/#{attachment.filename}"

    assert_response :redirect
    assert_equal url, response.location
  end

  def test_api_show_includes_the_presigned_url_only_when_the_attachment_is_visible
    Setting.rest_api_enabled = '1'
    attachment = cloud_fixture
    url = 'http://127.0.0.1:9000/redmine-attachments/redmine/files/2026/09/notes.txt?X-Amz-Signature=sekret'
    stub_direct_url(url)

    get "/attachments/#{attachment.id}.xml",
        headers: {
          'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials('jsmith', 'jsmith')
        }

    assert_response :success
    assert_includes response.body, 'direct_content_url'
    assert_includes response.body, '127.0.0.1:9000'

    Issue.where(id: attachment.container_id).update_all(is_private: true, assigned_to_id: nil)
    get "/attachments/#{attachment.id}.xml",
        headers: {
          'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials('someone', 'foo')
        }

    assert_response :forbidden
    refute_includes response.body, 'sekret'
    refute_includes response.body, 'direct_content_url'
  end

  def test_non_admin_cannot_open_plugin_settings
    assert_not Redmine::Plugin.find(:redmine_cloud_attachment).configurable?
    log_user('jsmith', 'jsmith')

    get '/settings/plugin/redmine_cloud_attachment'

    assert_response :forbidden
  end

  def test_admin_plugin_settings_are_not_a_form
    log_user('admin', 'admin')

    get '/settings/plugin/redmine_cloud_attachment'

    assert_response :not_found
  end

  def test_settings_post_without_a_csrf_token_is_rejected
    log_user('admin', 'admin')
    before = Setting.where(name: 'plugin_redmine_cloud_attachment').count
    ActionController::Base.allow_forgery_protection = true

    post '/settings/plugin/redmine_cloud_attachment', params: { settings: { bucket: 'evil-bucket' } }

    assert_response :unprocessable_entity
    assert_equal before, Setting.where(name: 'plugin_redmine_cloud_attachment').count
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  private

  def cloud_fixture
    attachment = Attachment.find(1)
    attachment.update_columns(
      disk_filename: 's3_notes.txt',
      filename: 'notes.txt',
      content_type: 'text/plain',
      filesize: 5
    )
    attachment
  end

  def stub_direct_url(url)
    Thread.current[:rca_stub_config] = true
    Thread.current[:rca_cloud_config] = MINIO_CONFIG
    Thread.current[:rca_stub_url] = true
    Thread.current[:rca_direct_url] = url
  end
end

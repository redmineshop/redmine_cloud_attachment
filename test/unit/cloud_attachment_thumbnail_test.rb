# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class CloudAttachmentThumbnailTest < ActiveSupport::TestCase
  def test_text_cloud_attachment_does_not_download_for_a_thumbnail
    attachment = Attachment.new(
      filename: 'notes.txt',
      disk_filename: 's3_notes.txt',
      content_type: 'text/plain'
    )
    calls = 0
    attachment.define_singleton_method(:diskfile) do
      calls += 1
      '/tmp/should-not-be-read'
    end

    assert_nil attachment.thumbnail(size: 100)
    assert_equal 0, calls
  end

  def test_thumbnail_uses_the_cloud_tempfile
    source = Tempfile.new(['cloud-src', '.png'])
    source.write('not-a-real-png')
    source.close
    attachment = Attachment.new(
      filename: 'notes.png',
      disk_filename: 's3_notes.png',
      content_type: 'image/png',
      filesize: 12,
      digest: 'abc123'
    )
    attachment.define_singleton_method(:diskfile) { source.path }
    attachment.define_singleton_method(:thumbnailable?) { true }
    attachment.define_singleton_method(:readable?) { true }
    target = File.join(Dir.tmpdir, "cloud-thumb-#{Process.pid}-#{attachment.object_id}.thumb")
    attachment.define_singleton_method(:thumbnail_path) { |_size| target }
    seen = nil
    Redmine::Thumbnail.expects(:generate).with do |path, dest, size, _pdf|
      seen = [path, dest, size]
      true
    end.returns(target)

    assert_equal target, attachment.thumbnail(size: 120)
    assert_equal [source.path, target, 150], seen
    local = File.join(Attachment.storage_path, attachment.disk_directory.to_s, attachment.disk_filename.to_s)
    refute_equal local, seen[0]
  ensure
    source&.close
    source&.unlink
    FileUtils.rm_f(target) if target
  end

  def test_thumbnail_returns_nil_when_the_cloud_read_fails
    attachment = Attachment.new(
      filename: 'notes.png',
      disk_filename: 's3_notes.png',
      content_type: 'image/png'
    )
    attachment.define_singleton_method(:thumbnailable?) { true }
    attachment.define_singleton_method(:readable?) { true }
    attachment.define_singleton_method(:diskfile) { nil }

    assert_nil attachment.thumbnail(size: 100)
  end
end

# frozen_string_literal: true

namespace :attachments do
  desc <<~DESC.gsub(/\s+/, ' ').strip
    DANGEROUS: Prefix disk_filename with cloud storage identifier (s3_/gcs_/azure_)
    for rows that are not already prefixed. Only run after migrating existing
    local files into the configured cloud backend. Requires CONFIRM=1.
  DESC
  task prefix_cloud_filenames: :environment do
    unless ENV['CONFIRM'] == '1'
      abort <<~MSG
        Refusing to run. This task rewrites Attachment#disk_filename and can mark
        local-only files as cloud-backed incorrectly.

        After you have copied files to the cloud backend, re-run with:
          CONFIRM=1 bundle exec rake attachments:prefix_cloud_filenames RAILS_ENV=production
      MSG
    end

    storage = Redmine::Configuration['storage'].to_s
    prefix = case storage
             when 's3', 'gcs', 'azure'
               "#{storage}_"
             end

    unless prefix
      abort "Unsupported or missing storage backend: #{storage.inspect}"
    end

    puts "Updating attachments for storage=#{storage}..."

    updated = 0
    Attachment.find_each do |attachment|
      next if attachment.disk_filename.blank?
      next if attachment.disk_filename.start_with?(prefix)
      next if attachment.disk_filename.match?(/^(s3|gcs|azure)_/)

      new_filename = "#{prefix}#{attachment.disk_filename}"
      attachment.update_column(:disk_filename, new_filename)
      puts "Updated ##{attachment.id} -> #{new_filename}"
      updated += 1
    end

    puts "Done. Total attachments updated: #{updated}"
  end
end

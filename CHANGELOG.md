# Changelog — Redmine Cloud Attachment

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-07-24

### Changed

- **Plugin rename**: directory / plugin id `redmine_cloud_attachment_pro` → `redmine_cloud_attachment`
- Ruby module `RedmineCloudAttachmentPro` → `RedmineCloudAttachment`
- Display name: "Redmine Cloud Attachment" (drop "Pro")
- Config key preference: `Redmine::Configuration['cloud_attachment']` (falls back to legacy `cloud_attachment_pro`)
- Canonical GitHub repo: https://github.com/redmineshop/redmine_cloud_attachment

### Upgrade notes

1. Stop Redmine.
2. Rename the plugin folder:
   ```bash
   mv plugins/redmine_cloud_attachment_pro plugins/redmine_cloud_attachment
   ```
   Or remove the old folder and install the new package into `plugins/redmine_cloud_attachment`.
3. Restart Redmine.
4. Optional: rename `cloud_attachment_pro:` → `cloud_attachment:` in `config/configuration.yml`.

## [1.1.1] — 2026-07-19

### Added

- First community release via RedmineShop. Based on [railsfactory-sivamanikandan/redmine_cloud_attachment_pro](https://github.com/railsfactory-sivamanikandan/redmine_cloud_attachment_pro) (MIT), extended for S3 presigned URL support.

### Features

- Multi-backend cloud storage: AWS S3, Google Cloud Storage, Azure Blob
- Presigned URL downloads (offload bandwidth from Redmine)
- Thumbnail generation for cloud-stored images
- Compatible with Redmine 5.0.x and 6.x

[1.2.0]: https://github.com/redmineshop/redmine_cloud_attachment/releases/tag/v1.2.0
[1.1.1]: https://github.com/redmineshop/redmine_cloud_attachment/releases/tag/v1.1.1

# Changelog — Redmine Cloud Attachment

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.2] — 2026-07-24

### Added

- S3-compatible / MinIO support via `s3.endpoint`, `s3.force_path_style`, and optional `s3.public_endpoint` for browser-reachable presigned URLs

## [1.2.1] — 2026-07-24

### Fixed

- Azure credentials: accept both `storage_account_name` / `storage_access_key` (sample) and legacy `account_name` / `access_key`
- Streaming uploads with chunked SHA256 — large files no longer load entirely into memory
- Lazy-load cloud SDKs (`aws-sdk-s3`, `google-cloud-storage`, `azure-storage-blob`) only for the configured backend
- README upgrade path from `redmine_cloud_attachment_pro` restored
- `attachments:prefix_cloud_filenames` requires `CONFIRM=1` and documents the data risk
- Controller/helper patches use `prepend` + `super`; remove double-include and `_pro` aliases
- Apply patches via `after_initialize` on Zeitwerk (Redmine 6+) so methods load in production/test
- Attachment patch uses `prepend` so local `readable?`/`thumbnail` call Redmine core via `super` (fixes 500 on `/attachments/thumbnail/...` with local storage)
- Docs no longer claim an Admin → Plugins → Configure UI (config is YAML-only)

### Changed

- Pin `google-cloud-storage` to `~> 1.47`
- S3 client supports IAM instance profile when access keys are omitted

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

[1.2.2]: https://github.com/redmineshop/redmine_cloud_attachment/releases/tag/v1.2.2
[1.2.1]: https://github.com/redmineshop/redmine_cloud_attachment/releases/tag/v1.2.1
[1.2.0]: https://github.com/redmineshop/redmine_cloud_attachment/releases/tag/v1.2.0
[1.1.1]: https://github.com/redmineshop/redmine_cloud_attachment/releases/tag/v1.1.1

# Redmine Cloud Attachment — S3, GCS & Azure Storage for Redmine

[![Community · Free forever](https://img.shields.io/badge/Community-Free%20forever-brightgreen)](https://redmineshop.com/products/redmine-cloud-attachment)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE.txt)
[![CI](https://github.com/redmineshop/redmine_cloud_attachment/actions/workflows/ci.yml/badge.svg)](https://github.com/redmineshop/redmine_cloud_attachment/actions/workflows/ci.yml)

**Last maintained:** 2026-09-22

**Source on GitHub:** [github.com/redmineshop/redmine_cloud_attachment](https://github.com/redmineshop/redmine_cloud_attachment)

S3 MinIO GCS Azure attachments for Redmine.

Store Redmine issue attachments in cloud object storage — AWS S3, MinIO, Google Cloud Storage, or Azure Blob — instead of local disk. Supports presigned URLs for secure, time-limited direct download links that bypass your Redmine server.

## Features

- Route Redmine file uploads directly to AWS S3, GCS, or Azure Blob
- Presigned URL downloads — files served directly from cloud, not through Redmine server
- Streaming uploads (SHA256 digest without loading the whole file into memory)
- Configurable via `config/configuration.yml` (no Admin UI settings page)
- Compatible with Redmine's built-in attachment management UI

## Requirements

- Redmine 5.0.x or 6.x
- Ruby 3.0+
- AWS S3 bucket (+ IAM credentials or instance profile), GCS bucket, or Azure Storage account

### IAM (S3) minimum

Grant `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on your attachments bucket/prefix.

## Installation

Clone from GitHub, then install gems:

```bash
cd /path/to/redmine/plugins
git clone https://github.com/redmineshop/redmine_cloud_attachment.git
cd /path/to/redmine
bundle install
# Restart your Redmine server
```

After restart, open **Administration → Plugins** and confirm **Redmine Cloud Attachment** is listed. There is no Configure link. Storage is `config/configuration.yml`.

See the [install guide](https://redmineshop.com/docs/cloud-attachment-install) for full instructions.

### Upgrading from `redmine_cloud_attachment_pro` (≤ 1.1.x)

```bash
mv plugins/redmine_cloud_attachment_pro plugins/redmine_cloud_attachment
bundle install
# Restart Redmine
```

Optional: rename `cloud_attachment_pro:` → `cloud_attachment:` in `configuration.yml` (legacy key still works).

## Configuration

Edit `config/configuration.yml` (see `config/configuration.yml.sample`). There is **no** “Configure” link under Administration → Plugins for this plugin.

### AWS S3 example

```yaml
production:
  storage: :s3
  s3:
    enabled: true
    access_key_id: <%= ENV["AWS_ACCESS_KEY"] %>
    secret_access_key: <%= ENV["AWS_SECRET_KEY"] %>
    bucket: <%= ENV["REDMINE_FILES_ATTACHEMENT_S3_BUCKET"] %>
    region: <%= ENV["AWS_REGION"] %>
    path: redmine/files
  cloud_attachment:
    presigned_url_expires_in: 15
```

Presigned download URLs expire after the configured minutes (default 15). Do not treat them as permanent links.

### MinIO / S3-compatible example

```yaml
production:
  storage: :s3
  s3:
    enabled: true
    access_key_id: minioadmin
    secret_access_key: minioadmin
    bucket: redmine-attachments
    region: us-east-1
    path: redmine/files
    endpoint: http://minio:9000
    # Host the browser can reach for presigned downloads (optional but required in Docker)
    public_endpoint: http://localhost:9000
    force_path_style: true
```

`endpoint` is used for put/get/delete from the Redmine process. When `public_endpoint` is set,
presigned download URLs are signed against that host instead (so redirects work outside Docker).

## Compatibility

`init.rb` does not set `requires_redmine`. Declared rows match the Requirements section: 5.0.x through 6.x. Redmine 7.0 is not a claimed target. Tested means a run pinned to that Redmine line. The demo image is official `redmine:latest` (tag not pinned), so a demo boot is not a pass for a specific row.

| Redmine | Declared | Tested |
|---------|----------|--------|
| 5.0.x   | Yes      | No — unverified |
| 5.1.x   | Yes      | No — unverified |
| 6.0.x   | Yes      | No — unverified |
| 6.1.x   | Yes      | No — unverified |
| 7.0.x   | No       | No — unverified |

## Screenshot

Administration → Plugins on demo Redmine. There is **no** Configure link — storage is `config/configuration.yml` (MinIO on the demo stack):

![Plugin listed under Administration → Plugins](screenshots/admin-plugins.png)

Issue Files field after choosing a file:

![Issue edit Files field](screenshots/issue-edit-files.png)

Attachments list after save:

![Issue attachments after upload](screenshots/issue-attachment.png)

Images are crops from a demo Redmine with MinIO. The Redmine version in the capture was not recorded. `issue-attachment.png` is a short header crop; a full attachments list is still TODO. A full-page screenshot is still TODO.

## Tests

Unit + integration tests live under `test/` (MiniTest). They do not boot Redmine 5.0, 5.1, 6.0, 6.1, or 7.0.

Public GitHub Actions (`.github/workflows/ci.yml`) runs Ruby syntax checks only (`ruby -c`).

Run them from a Redmine tree with this plugin installed:

```bash
bundle exec rake redmine:plugins:test NAME=redmine_cloud_attachment RAILS_ENV=test
```

## Limits

- No **Administration → Plugins → Configure** screen. All storage settings are in `config/configuration.yml`.
- Presigned download URLs expire (default 15 minutes). They are not permanent links.
- A mis-set `endpoint` or `public_endpoint` breaks downloads inside Docker. See the MinIO example above.
- Install notes: [cloud attachment install](https://redmineshop.com/docs/cloud-attachment-install).

## Troubleshooting

See [docs/cloud-attachment-troubleshooting](https://redmineshop.com/docs/cloud-attachment-troubleshooting) or open an issue at [GitHub Issues](https://github.com/redmineshop/redmine_cloud_attachment/issues).

## License

MIT — see [LICENSE.txt](LICENSE.txt). Based on [railsfactory-sivamanikandan/redmine_cloud_attachment_pro](https://github.com/railsfactory-sivamanikandan/redmine_cloud_attachment_pro).

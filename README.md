# Redmine Cloud Attachment — S3, GCS & Azure Storage for Redmine

[![Community · Free forever](https://img.shields.io/badge/Community-Free%20forever-brightgreen)](https://redmineshop.com/products/redmine-cloud-attachment)
[![Redmine 5.x/6.x](https://img.shields.io/badge/Redmine-5.x%20%7C%206.x-blue)](https://redmineshop.com/docs/compatibility)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE.txt)

**Download via RedmineShop:** [redmineshop.com/products/redmine-cloud-attachment](https://redmineshop.com/products/redmine-cloud-attachment)

Store Redmine issue attachments in cloud object storage — AWS S3, Google Cloud Storage, or Azure Blob — instead of local disk. Supports presigned URLs for secure, time-limited direct download links that bypass your Redmine server.

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

Download the SHA256-verified package from [RedmineShop](https://redmineshop.com/products/redmine-cloud-attachment), then:

```bash
# From your Redmine root
tar -xzf redmine_cloud_attachment-1.2.2.tar.gz -C plugins/
bundle install
# Restart your Redmine server
```

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

## Troubleshooting

See [docs/cloud-attachment-troubleshooting](https://redmineshop.com/docs/cloud-attachment-troubleshooting) or open an issue at [GitHub Issues](https://github.com/redmineshop/redmine_cloud_attachment/issues).

## License

MIT — see [LICENSE.txt](LICENSE.txt). Based on [railsfactory-sivamanikandan/redmine_cloud_attachment_pro](https://github.com/railsfactory-sivamanikandan/redmine_cloud_attachment_pro).

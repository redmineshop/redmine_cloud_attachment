# Screenshots — Redmine Cloud Attachment

Captured by Playwright against demo Redmine + MinIO.

Refresh is **private-monorepo only** (`redmineshop/redmineshop` harness). A public clone of this plugin cannot run that job.

Output:

- `admin-plugins.png` — Administration → Plugins row (no Configure link; config is YAML)
- `issue-edit-files.png` — issue edit Files field with the harness fixture queued
- `issue-attachment.png` — issue attachments list after upload (download 302s to MinIO)

# Screenshots — Redmine Cloud Attachment

Captured by the plugin quality harness (Playwright) against demo Redmine + MinIO.

Refresh:

```bash
./demo/scripts/run-plugin-e2e.sh
```

Output:

- `admin-plugins.png` — Administration → Plugins row (no Configure link; config is YAML)
- `issue-edit-files.png` — issue edit Files field with the harness fixture queued
- `issue-attachment.png` — issue attachments list after upload (download 302s to MinIO)

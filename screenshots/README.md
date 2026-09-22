# Screenshots — Redmine Cloud Attachment

Captured by Playwright against demo Redmine + MinIO.

Refresh is **private-monorepo only** (`redmineshop/redmineshop` harness). A public clone of this plugin cannot run that job.

Output:

- `issue-attachment.png` — full issue page after upload (subject + attachment row). No bucket label in the UI.
- `issue-edit-files.png` — full issue edit page with the harness PNG queued
- `admin-plugins.png` — Administration → Plugins (no Configure link; config is YAML)
- `settings-storage.png` — not captured. There is no plugin settings screen; rendering `configuration.yml` would show MinIO keys.

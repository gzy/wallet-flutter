# OTA 下载页版本号同步

本目录用于 iOS OTA（`manifest.plist`）与下载页（`index.html`）。

发新版时请按以下顺序同步版本号，避免下载页显示与包内版本不一致：

1. 修改根目录 `pubspec.yaml` 的 `version:`（形如 `1.2.3+45`）
2. 运行同步脚本（会自动更新 `index.html` 与 `manifest.plist`）：

```bash
dart run tools/sync_ota_version.dart
```

同步内容：

- `deploy/ota/index.html`: `APP_VERSION_NAME` / `APP_BUILD_NUMBER`
- `deploy/ota/manifest.plist`: `bundle-version`


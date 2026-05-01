import 'dart:io';

/// Syncs version info from `pubspec.yaml` into OTA download assets:
/// - `deploy/ota/index.html` (APP_VERSION_NAME / APP_BUILD_NUMBER / APP_RELEASE_DATE 中文年月日=本机当天)
/// - `deploy/ota/manifest.plist` (`bundle-version` = iOS build / `+` 后缀；
///   `subtitle` = 营销版本号如 1.0.1，因 Apple 要求 `bundle-version` 必须对齐 CFBundleVersion)
///
/// Usage:
///   dart run tools/sync_ota_version.dart
void main(List<String> args) {
  final root = Directory.current.path;
  final pubspec = File(_join(root, 'pubspec.yaml'));
  final indexHtml = File(_join(root, 'deploy', 'ota', 'index.html'));
  final manifest = File(_join(root, 'deploy', 'ota', 'manifest.plist'));

  if (!pubspec.existsSync()) {
    stderr.writeln('Missing pubspec.yaml at: ${pubspec.path}');
    exitCode = 2;
    return;
  }
  if (!indexHtml.existsSync()) {
    stderr.writeln('Missing OTA index.html at: ${indexHtml.path}');
    exitCode = 2;
    return;
  }
  if (!manifest.existsSync()) {
    stderr.writeln('Missing OTA manifest.plist at: ${manifest.path}');
    exitCode = 2;
    return;
  }

  final versionLine = pubspec.readAsLinesSync().cast<String?>().firstWhere(
      (l) => l != null && RegExp(r'^\s*version\s*:').hasMatch(l),
      orElse: () => null);

  if (versionLine == null) {
    stderr.writeln('No "version:" field found in pubspec.yaml');
    exitCode = 2;
    return;
  }

  final raw = versionLine.split(':').sublist(1).join(':').trim();
  // Expected: 1.2.3+45  (build number optional but we rely on it for OTA)
  final parts = raw.split('+');
  final name = parts.first.trim();
  final build = (parts.length >= 2 ? parts[1].trim() : '').trim();

  if (!_isSemverLike(name)) {
    stderr.writeln('Unexpected version name format: "$name" (from "$raw")');
    exitCode = 2;
    return;
  }
  if (build.isEmpty || int.tryParse(build) == null) {
    stderr.writeln(
        'Missing/invalid build number in pubspec.yaml version: "$raw"');
    stderr.writeln('Expected format like: version: 1.2.3+45');
    exitCode = 2;
    return;
  }

  final releaseDateZh = _zhDateTodayLocal();

  final htmlBefore = indexHtml.readAsStringSync();
  final htmlAfter = _updateIndexHtml(
    htmlBefore,
    name: name,
    build: build,
    releaseDateZh: releaseDateZh,
  );
  if (htmlAfter == htmlBefore) {
    stderr.writeln(
        'No changes made to index.html (constants not found?). Check file format.');
  } else {
    indexHtml.writeAsStringSync(htmlAfter);
    stdout.writeln(
        'Updated ${indexHtml.path}: $name+$build, APP_RELEASE_DATE=$releaseDateZh',
    );
  }

  final manifestBefore = manifest.readAsStringSync();
  final manifestAfter = _updateManifestPlist(manifestBefore, name: name, build: build);
  if (manifestAfter == manifestBefore) {
    stderr.writeln(
        'No changes made to manifest.plist (bundle-version/subtitle not found?). Check file format.');
  } else {
    manifest.writeAsStringSync(manifestAfter);
    stdout.writeln(
        'Updated ${manifest.path}: bundle-version=$build, subtitle=$name',
    );
  }
}

String _updateIndexHtml(
  String input, {
  required String name,
  required String build,
  required String releaseDateZh,
}) {
  var out = input;

  out = out.replaceFirstMapped(
    RegExp(r'(\bvar\s+APP_VERSION_NAME\s*=\s*")[^"]*(";)'),
    (m) => '${m.group(1)}$name${m.group(2)}',
  );

  out = out.replaceFirstMapped(
    RegExp(r'(\bvar\s+APP_BUILD_NUMBER\s*=\s*")[^"]*(";)'),
    (m) => '${m.group(1)}$build${m.group(2)}',
  );

  out = out.replaceFirstMapped(
    RegExp(r'(\bvar\s+APP_RELEASE_DATE\s*=\s*")[^"]*(";)'),
    (m) => '${m.group(1)}$releaseDateZh${m.group(2)}',
  );

  return out;
}

/// 本机本地日历日，用于下载页「更新 yyyy年m月d日」。
String _zhDateTodayLocal() {
  final n = DateTime.now();
  return '${n.year}年${n.month}月${n.day}日';
}

String _updateManifestPlist(String input,
    {required String name, required String build}) {
  var out = input.replaceFirstMapped(
    RegExp(
      r'(<key>\s*bundle-version\s*</key>\s*<string>)[^<]*(</string>)',
      multiLine: true,
    ),
    (m) => '${m.group(1)}$build${m.group(2)}',
  );
  out = out.replaceFirstMapped(
    RegExp(
      r'(<key>\s*subtitle\s*</key>\s*<string>)[^<]*(</string>)',
      multiLine: true,
    ),
    (m) => '${m.group(1)}$name${m.group(2)}',
  );
  return out;
}

bool _isSemverLike(String s) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(s);

String _join(String a, String b, [String? c, String? d, String? e, String? f]) {
  final parts = <String>[a, b];
  for (final x in [c, d, e, f]) {
    if (x != null) parts.add(x);
  }
  return parts.join(Platform.pathSeparator);
}

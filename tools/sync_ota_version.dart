import 'dart:io';

/// Syncs version info from `pubspec.yaml` into OTA download assets:
/// - `deploy/ota/index.html` (APP_VERSION_NAME / APP_BUILD_NUMBER)
/// - `deploy/ota/manifest.plist` (bundle-version)
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

  final htmlBefore = indexHtml.readAsStringSync();
  final htmlAfter = _updateIndexHtml(htmlBefore, name: name, build: build);
  if (htmlAfter == htmlBefore) {
    stderr.writeln(
        'No changes made to index.html (constants not found?). Check file format.');
  } else {
    indexHtml.writeAsStringSync(htmlAfter);
    stdout.writeln('Updated ${indexHtml.path}: $name+$build');
  }

  final manifestBefore = manifest.readAsStringSync();
  final manifestAfter = _updateManifestPlist(manifestBefore, build: build);
  if (manifestAfter == manifestBefore) {
    stderr.writeln(
        'No changes made to manifest.plist (bundle-version not found?). Check file format.');
  } else {
    manifest.writeAsStringSync(manifestAfter);
    stdout.writeln('Updated ${manifest.path}: bundle-version=$build');
  }
}

String _updateIndexHtml(String input,
    {required String name, required String build}) {
  var out = input;
  out = out.replaceFirst(
    RegExp(r'(\bvar\s+APP_VERSION_NAME\s*=\s*")[^"]*(";)'),
    r'$1' + name + r'$2',
  );
  out = out.replaceFirst(
    RegExp(r'(\bvar\s+APP_BUILD_NUMBER\s*=\s*")[^"]*(";)'),
    r'$1' + build + r'$2',
  );
  return out;
}

String _updateManifestPlist(String input, {required String build}) {
  // Replace the value following <key>bundle-version</key> ... <string>...</string>
  final re = RegExp(
    r'(<key>\s*bundle-version\s*</key>\s*<string>)[^<]*(</string>)',
    multiLine: true,
  );
  return input.replaceFirst(re, r'$1' + build + r'$2');
}

bool _isSemverLike(String s) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(s);

String _join(String a, String b, [String? c, String? d, String? e, String? f]) {
  final parts = <String>[a, b];
  for (final x in [c, d, e, f]) {
    if (x != null) parts.add(x);
  }
  return parts.join(Platform.pathSeparator);
}

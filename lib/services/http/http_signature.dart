import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'api_config.dart';
import 'http_sign_context.dart';

/// 当前 [kWalletApiBase] 对应 host，且已配置 [kHttpSignSecret] 时才参与验签。
bool httpSignatureAppliesToHost(String host) {
  if (kHttpSignSecret.isEmpty) return false;
  final expected = Uri.parse(kWalletApiBase).host;
  if (expected.isEmpty) return false;
  return host.toLowerCase() == expected.toLowerCase();
}

/// `X-Sign = MD5( Base64( HMAC_SHA256( MD5(strToSign的UTF-8) 的32位小写hex字符串UTF-8, secret ) )` 的32位小写hex。
String httpComputeXSign(String strToSign, String secret) {
  final innerDigest = md5.convert(utf8.encode(strToSign));
  final innerHex = _bytesToHexLower(innerDigest.bytes);
  final hmac = Hmac(sha256, utf8.encode(secret));
  final hmacOut = hmac.convert(utf8.encode(innerHex));
  final b64 = base64Encode(hmacOut.bytes);
  final finalDigest = md5.convert(utf8.encode(b64));
  return _bytesToHexLower(finalDigest.bytes);
}

String _bytesToHexLower(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// 与 Query 一致：取 URI 整串中 `?` 后、`#` 前的原始片段（与 Java `getQueryString()` 对齐）。
String httpSignatureRawQuery(Uri uri) {
  if (!uri.hasQuery) return '';
  final s = uri.toString();
  final q = s.indexOf('?');
  if (q < 0) return '';
  final h = s.indexOf('#', q + 1);
  return h < 0 ? s.substring(q + 1) : s.substring(q + 1, h);
}

/// 第一层 key 字典序，value 全部转字符串；紧凑 JSON。
String httpKeySortedJson(Map<String, dynamic> map) {
  final keys = map.keys.toList()..sort();
  final out = <String, String>{};
  for (final k in keys) {
    out[k] = _valueToSignString(map[k]);
  }
  return jsonEncode(out);
}

String _valueToSignString(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  if (v is Map || v is List) return jsonEncode(v);
  return v.toString();
}

/// 构建 `strToSign`；[keySortedJson] 非空时追加 `\n` + 内容（POST JSON）。
String httpBuildStringToSign({
  required int timestampSec,
  required Uri uri,
  required String nonce,
  String? keySortedJson,
}) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = httpSignatureRawQuery(uri);
  final base = '$timestampSec\n$path\n$query\n$nonce';
  if (keySortedJson == null || keySortedJson.isEmpty) {
    return base;
  }
  return '$base\n$keySortedJson';
}

/// 若 host 需签名且为 [http.Request]，写入全部约定 Header（含 X-Sign）。
void httpApplySignatureHeaders(http.Request request) {
  if (!httpSignatureAppliesToHost(request.url.host)) {
    return;
  }

  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  const uuid = Uuid();
  final nonce = uuid.v4();

  String? keySorted;
  final method = request.method.toUpperCase();
  if (method == 'POST' &&
      request.body.isNotEmpty &&
      _contentTypeIsJson(request.headers['Content-Type'])) {
    try {
      final decoded = jsonDecode(request.body);
      if (decoded is Map<String, dynamic>) {
        keySorted = httpKeySortedJson(decoded);
      }
    } catch (_) {
      // 非 JSON 体不参与 keySortedJson；与后端「能取到 JSON body」一致即可
    }
  }

  final strToSign = httpBuildStringToSign(
    timestampSec: ts,
    uri: request.url,
    nonce: nonce,
    keySortedJson: keySorted,
  );
  final sign = httpComputeXSign(strToSign, kHttpSignSecret);

  request.headers['X-Sign'] = sign;
  request.headers['X-Sign-Version'] = '1';
  request.headers['X-Timestamp'] = ts.toString();
  request.headers['X-Nonce'] = nonce;
  request.headers['X-Device-Id'] = HttpSignContext.deviceId;
  request.headers['X-App-Id'] = HttpSignContext.appId;
  request.headers['X-App-Version'] = HttpSignContext.appVersion;
}

bool _contentTypeIsJson(String? ct) {
  if (ct == null || ct.isEmpty) return false;
  final lower = ct.toLowerCase();
  return lower.contains('application/json') ||
      lower.contains('text/json') ||
      lower.contains('+json');
}

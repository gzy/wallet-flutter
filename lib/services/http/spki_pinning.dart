import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

/// 计算 X.509 证书 SubjectPublicKeyInfo(SPKI) 的 SHA-256(Base64)。
///
/// 这就是常说的 “SPKI pin”：
/// - 服务端续期换证但复用同一把 key：pin 不变
/// - 轮换 key：pin 会变化（需预埋备份 pin）
class SpkiPinning {
  static String spkiSha256Base64(Uint8List certificateDer) {
    final spkiDer = _extractSpkiDer(certificateDer);
    return base64Encode(sha256.convert(spkiDer).bytes);
  }

  static String spkiSha256Base64FromPem(String certificatePem) {
    final certDer = _pemToDer(certificatePem);
    return spkiSha256Base64(certDer);
  }

  static Uint8List _pemToDer(String pem) {
    final normalized = pem
        .replaceAll('\r', '')
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .trim();
    final b64 = normalized.replaceAll('\n', '');
    return Uint8List.fromList(base64Decode(b64));
  }

  /// 从证书 DER 中提取 SPKI 的 DER（SubjectPublicKeyInfo）。
  ///
  /// X.509 Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
  /// tbsCertificate 中的 subjectPublicKeyInfo 通常位于：
  ///   [0] version (optional, explicit) -> 会导致后续 index +1
  ///   serialNumber
  ///   signature
  ///   issuer
  ///   validity
  ///   subject
  ///   subjectPublicKeyInfo  <-- 我们要的
  static Uint8List _extractSpkiDer(Uint8List certificateDer) {
    final cert = ASN1Parser(certificateDer).nextObject() as ASN1Sequence;
    final tbs = cert.elements[0] as ASN1Sequence;

    final tbsElements = tbs.elements;
    var idx = 0;
    // version 是 [0] EXPLICIT（CONTEXT-SPECIFIC, CONSTRUCTED）。
    // 证书里存在 version 时，首元素 tag 通常为 0xA0。
    if (tbsElements.isNotEmpty && tbsElements[0].tag == 0xA0) {
      idx = 1;
    }

    // subjectPublicKeyInfo 在 subject 后面：serial/signature/issuer/validity/subject -> +5
    final spki = tbsElements[idx + 5];
    return Uint8List.fromList(spki.encodedBytes);
  }
}


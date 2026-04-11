import 'package:bip39_plus/bip39_plus.dart' as bip39;

class MnemonicService {
  MnemonicService._();

  /// 默认 12 词（128 bit entropy），与 BIP39 一致单次随机生成。
  static String generateMnemonic() {
    return bip39.generateMnemonic(strength: 128);
  }

  static bool validateMnemonic(String phrase) {
    return bip39.validateMnemonic(phrase.trim());
  }

  /// 与 [importWallet] 中空格规则一致，并统一小写，用于判断两串助记词是否实质相同。
  static String normalizeForCompare(String phrase) {
    return phrase.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  static String mnemonicToSeedHex(String mnemonic) {
    return bip39.mnemonicToSeedHex(mnemonic.trim());
  }
}

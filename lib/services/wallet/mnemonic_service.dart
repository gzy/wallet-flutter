import 'package:bip39_plus/bip39_plus.dart' as bip39;

class MnemonicService {
  MnemonicService._();

  /// 默认 12 词（128 bit entropy）
  static String generateMnemonic() {
    return bip39.generateMnemonic(strength: 128);
  }

  static bool validateMnemonic(String phrase) {
    return bip39.validateMnemonic(phrase.trim());
  }

  static String mnemonicToSeedHex(String mnemonic) {
    return bip39.mnemonicToSeedHex(mnemonic.trim());
  }
}

/// 后端环境与签名密钥（编译期注入）。
///
/// ## Flutter / Xcode / Gradle 示例
///
/// ```bash
/// flutter run --dart-define=WALLET_API_BASE=https://api-wallet-test.uone.me \
///   --dart-define=HTTP_SIGN_SECRET=你的密钥
/// ```
///
/// ### TLS / 连接异常（如 `WRONG_VERSION_NUMBER`）
///
/// - **`WALLET_HTTP_CLOSE_CONNECTION=true`**（默认）：对同钱包 host 的请求加 `Connection: close`，
///   减轻 keep-alive 复用到已被网关关闭的连接上的问题。
/// - **`WALLET_HTTP_CLOSE_CONNECTION=false`**：恢复长连接（略省握手）。
/// - **`HTTP_DISABLE_SPKI_PINNING=true`**：关闭 SPKI 钉扎，仅用系统 CA（仅建议本地排障）。
///
/// Android release（`android/app/build.gradle.kts`）可在 `defaultConfig` / `buildTypes` 里为
/// `dart-define` 配置与 CI 一致的环境变量。
///
/// ## 优先级
///
/// - **API 根地址**：[kWalletApiBase] ← `WALLET_API_BASE` → `MARKET_API_BASE`（兼容旧名）→ 默认测试地址
/// - **签名密钥**：[kHttpSignSecret] ← `HTTP_SIGN_SECRET` → 默认测试密钥（生产务必注入，勿依赖默认）
library;

/// 钱包 / 行情 / 链列表等共用后端根 URL（**无**尾部 `/`）。
///
/// 覆盖优先级：`WALLET_API_BASE` > `MARKET_API_BASE` > 默认。
const String kWalletApiBase = String.fromEnvironment(
  'WALLET_API_BASE',
  defaultValue: String.fromEnvironment(
    'MARKET_API_BASE',
    defaultValue: 'https://api-wallet-test.uone.me',
  ),
);

/// 与后端 `http.sign.secret` 一致；空字符串表示不在请求中加签（仅本地调试可用）。
///
/// 生产、TestFlight、上架包请通过 CI 注入，**不要**依赖默认值。
const String kHttpSignSecret = String.fromEnvironment(
  'HTTP_SIGN_SECRET',
  defaultValue: 'uMMhDok6WMOY25FR',
);

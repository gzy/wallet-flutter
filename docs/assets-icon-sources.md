# 币种 / 网络图标资源来源（维护用）

工程内图标**不来自运行时「爬网页」**，都是打包进 App 的静态文件。新增币种或新链时，请从下面**固定来源**取图，风格与许可一致，避免随机搜索引擎结果。

---

## 1. 币种图标 `assets/coins/*.svg`

| 项 | 说明 |
|----|------|
| **对应组件** | `lib/widgets/coin_icon.dart` → `CoinIcon` |
| **文件格式** | SVG（彩色） |
| **与当前资源关系** | 现有文件的 `viewBox`、`32×32` 风格及路径结构与下列仓库的 **`svg/color/`** 彩色 SVG 一致；历史提交仅写「开源 SVG」，此处补全可查 URL。 |
| **推荐来源（唯一主源）** | **[spothq/cryptocurrency-icons](https://github.com/spothq/cryptocurrency-icons)**（npm 包名常为 `cryptocurrency-icons`，亦可能跳转至继任维护仓库，以 README 为准） |
| **取图路径（仓库内）** | `svg/color/<代币符号小写>.svg`  
  例：`btc.svg`、`eth.svg`、`usdt.svg`；Polygon 符号若后端为 `POL`，图标文件可能仍名为 `matic.svg`（与 npm 包内命名一致时需对照 `manifest.json`）。 |
| **CDN 直链示例（仅参考，发版以落盘到 `assets/coins` 为准）** | `https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@0.18.1/svg/color/eth.svg`（版本号可到 [Releases](https://github.com/spothq/cryptocurrency-icons/releases) 核对） |
| **许可** | 以仓库根目录 **LICENSE** 为准（多为 **CC0**，可自由使用；仍需保留第三方品牌自身限制常识）。 |

**新增币种步骤：** 从上述仓库 **`svg/color/`** 拷贝对应 ticker 的 svg → 放入 `assets/coins/` → 在 `CoinIcon._assetBySymbol` 增加 `符号大写 → 路径`。

---

## 2. 网络（链）图标 `assets/chains/*.png`

| 项 | 说明 |
|----|------|
| **对应组件** | `lib/widgets/chain_icon.dart` → `ChainIcon` |
| **文件格式** | PNG（工程内现为圆角裁切外的方形源图 + `ClipOval`） |
| **历史记录** | 引入提交未写明具体站点；以下为**推荐的统一供给侧**，便于以后扩展新链时「仍从同一地方拉」。 |
| **推荐来源（唯一主源）** | **[trustwallet/assets](https://github.com/trustwallet/assets)** → 目录 **`blockchains/<链目录名>/info/logo.png`** |
| **链目录名与后端 `chainCode` 对照（示例）** | `ETH` → `ethereum`；`BSC` → `smartchain`；`POL` / Polygon → `polygon`；`ARB` → `arbitrum`；`TRX` → `tron`；`SOL` → `solana`；`XRP` → `ripple`。  
  新链请到该仓库 `blockchains/` 下搜索官方链名，以 **实际文件夹名** 为准。 |
| **许可** | 以 [trustwallet/assets 仓库 LICENSE / 贡献须知](https://github.com/trustwallet/assets) 为准；多用于展示链标识时请遵守其对商标与分叉作品的要求。 |

**新增链步骤：** 从 **Trust Wallet `blockchains/.../info/logo.png`** 下载 → 存入 `assets/chains/`（命名与后端 `chainCode` 对齐，见现有 `arb.png`、`bsc.png` 等）→ 在 `ChainIcon._assetByChainCode` 增加映射。

---

## 3. 不要怎么做

- 不要用无版权说明的壁纸站、盗版图标包或随机 CDN，以免许可不清。
- 不要依赖「运行时抓 CoinGecko 图片 URL」作为主要方案（离线、改版、配额、合规都不好控）；若产品将来要做 CDN 兜底，再在单独设计文档里定义。

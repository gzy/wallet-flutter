# Chain Rules Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将“链类型 → 地址格式/展示/存储/校验/标签”的规则集中到一处，避免新增币种/链后出现写死 EVM、地址被强制补 `0x`、TRON 地址大小写被破坏、最近地址去重跨链污染等问题。

**Architecture:** 新增 `ChainRules` 作为唯一真相（Single Source of Truth），由链配置字段（`chainType` / `walletApiChainQuery`）推断 `ChainKind`，并提供地址规范化与 UI 文案/角标方法。业务层（存储/UI）禁止自行写 `if (TRON) ... else ...` 与写死 `EVM`，全部改为调用 `ChainRules`。

**Tech Stack:** Flutter/Dart, flutter_test

---

### Task 1: 新增统一链规则模块

**Files:**
- Create: `lib/services/wallet/chain_rules.dart`
- Test: `test/chain_rules_test.dart`

**Step 1: Write the failing test**

写用例覆盖：
- TRON 地址：不补 `0x`、不强制小写、非法字符校验返回 false
- EVM 地址：存储规范化应补 `0x` 且小写；UI 展示应补 `0x`
- 链识别：`TRX/TRON/...` → `ChainKind.tron`；其它默认 `evm`

**Step 2: Run test to verify it fails**

Run: `flutter test test/chain_rules_test.dart`
Expected: FAIL（模块不存在）

**Step 3: Write minimal implementation**

实现：
- `enum ChainKind { evm, tron, unknown }`
- `ChainRules.kindFromChainType(String?)`
- `ChainRules.kindFromChainQuery(String?)`
- `ChainRules.badgeLabel(ChainKind)`
- `ChainRules.normalizeAddressForStorage(ChainKind, String)`
- `ChainRules.formatAddressForUi(ChainKind, String)`
- `ChainRules.isValidAddress(ChainKind, String)`（EVM regex；TRON 调用 `isValidTronAddress`）

**Step 4: Run test to verify it passes**

Run: `flutter test test/chain_rules_test.dart`
Expected: PASS

---

### Task 2: 存储层统一使用 ChainRules 做最近地址规范化与去重

**Files:**
- Modify: `lib/services/wallet/secure_storage_service.dart`
- Test: `test/chain_rules_test.dart`（补充：TRON/EVM 的存储规范化差异）

**Step 1: Write failing test**

新增断言：
- `normalizeAddressForStorage(tron, 'T...')` 保持原样
- `normalizeAddressForStorage(evm, 'abc')` → `0xabc` 且小写

**Step 2: Implement**

将 `recordRecentRecipient` 内的地址规范化与去重 key 统一改为 `ChainRules.normalizeAddressForStorage(...)`。

**Step 3: Verify**

Run: `flutter test test/chain_rules_test.dart`
Expected: PASS

---

### Task 3: UI 层（地址簿/收款/交易详情）移除写死 EVM，统一走 ChainRules

**Files:**
- Modify: `lib/screens/address_book_screen.dart`
- Modify: `lib/screens/receive_screen.dart`
- Modify: `lib/screens/wallet_transaction_detail_screen.dart`
- Modify: `lib/screens/transfer_screen.dart`
- Modify: `lib/screens/coin_detail_screen.dart`
- Modify: `lib/screens/wallet_detail_screen.dart`（导出地址弹窗文案/展示）
- (Optional) Modify: `lib/screens/wallet_screen.dart`（标签展示）

**Step 1: Implementation**

逐个替换：
- 标签/角标：`ChainRules.badgeLabel(kind)`
- 地址展示：`ChainRules.formatAddressForUi(kind, addr)`
- 地址比较（仅 EVM 走 lower+0x）：使用 `normalizeAddressForStorage` 做比较 key

**Step 2: Run targeted tests**

Run: `flutter test`
Expected: PASS

---

### Task 4: 全局扫描与回归验证

**Files:**
- Modify: touched files above

**Step 1: Scan**

确保不再出现：
- TRON 地址被补 `0x`
- TRON 地址被 `.toLowerCase()`
- UI 文案/角标在 TRON 场景写死 `EVM`

**Step 2: Run**

Run: `flutter test`
Expected: PASS


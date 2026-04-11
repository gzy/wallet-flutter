# Mnemonic Backup Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 Flutter 移动端补齐与前端一致的助记词备份/验证流程，并从“创建钱包”链路串联可预览。

**Architecture:** 按前端路由拆成多个 Flutter `Screen`（方案 A）。每个 Screen 只负责一段 UI/交互；页面间用 `Navigator.push/pop` 串联；助记词先用 mock 数据。

**Tech Stack:** Flutter 3.16.x / Material 3 / 现有 `AppColors` 主题与页面结构

---

### Task 1: 调整 `WalletReadyScreen` 为前端 `/wallet-ready`

**Files:**
- Modify: `lib/screens/wallet_ready_screen.dart`

**Step 1: 实现 UI**
- 标题“您的钱包已准备就绪！”
- 文案说明助记词重要性
- 按钮：
  - “立即备份” → 进入备份流程起点
  - “跳过备份” → 返回首页钱包 Tab

**Step 2: 手动验证**
- iOS 模拟器进入 `WalletReadyScreen`，两按钮跳转正常

---

### Task 2: 实现备份流程 `/backup`（拆多个 Screen）

**Files:**
- Create: `lib/screens/backup/backup_prompt_screen.dart`
- Create: `lib/screens/backup/backup_method_screen.dart`
- Create: `lib/screens/backup/backup_password_screen.dart`
- Create: `lib/screens/backup/backup_uploading_screen.dart`

**Step 1: UI + 交互**
- Prompt：助记词未备份弹窗（跳过/备份 + 不再提示）
- Method：方式选择（iCloud / 手动备份；iCloud 可提示未实现）
- Password：创建备份密码（≥8 位，显示/隐藏，确认密码一致才可“下一步”）
- Warning：用 BottomSheet 呈现 3 条勾选，全部勾选后“立即备份”进入助记词展示页
- Uploading：上传中（可选；先做 UI，不接真实上传）

**Step 2: 手动验证**
- 从 `WalletReadyScreen` 进入备份流程，能一路走到助记词展示页

---

### Task 3: 实现助记词展示 `/backup/mnemonic`

**Files:**
- Create: `lib/screens/backup/mnemonic_show_screen.dart`

**Step 1: UI**
- 12 词网格（编号 + 单词），样式对齐前端：白底黑字、三列
- 推荐/避免提示区 + “了解更多助记词知识”
- 底部“下一步” → 验证页

**Step 2: 手动验证**
- 页面布局在竖屏 iPhone 安全区正常，不溢出

---

### Task 4: 实现助记词验证 `/backup/verify`

**Files:**
- Create: `lib/screens/backup/mnemonic_verify_screen.dart`

**Step 1: UI + 交互**
- 上方 12 个槽位（空态边框/填充白底黑字）
- “清空”按钮
- 下方乱序词按钮（已选置灰不可点）
- “验证”按钮：未完成禁用；完成后校验顺序
  - 正确：返回首页（钱包 Tab）
  - 错误：提示并清空

**Step 2: 手动验证**
- 正确/错误两种路径都验证一次

---

### Task 5: 串联现有“创建钱包”入口

**Files:**
- Modify: `lib/screens/add_wallet_screen.dart`

**Step 1: 跳转调整**
- 6 位密码输入完成后进入 `WalletReadyScreen`（保持）
- `WalletReadyScreen` 的“立即备份”进入备份流程起点

---

### Task 6: 运行与验证

**Step 1: 运行**
- Run: `flutter devices`
- Run: `flutter run -d "iPhone 16e"`

**Step 2: 验证清单**
- 从“添加钱包” → “创建新钱包” → 输入 6 位 → WalletReady
- 立即备份 → Prompt/Method/Password/Warning → MnemonicShow → Verify
- BottomNavigationBar 不再出现 `OVERFLOWED BY ...`


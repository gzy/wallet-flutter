# estimateGasV2 适配（EVM 优先 V2，失败回退）

## 背景

后端新增 `POST /api/app/wallet/estimateGasV2`，前端需要在打包/转账流程中使用该接口估算 gas。

约束/约定：

- **请求参数与旧接口一致**（`chain/coin/ownerAddress/toAddress/amount`）
- 若 EVM 改用 V2：**gas limit 的值取响应 `data.gasLimit`**
- 若 V2 不可用（灰度、网关、异常等）：前端应**自动回退旧版** `estimateGas`

## 影响范围

- `lib/services/wallet/wallet_estimate_gas_service.dart`
  - 新增 V2 endpoint 调用方法 `estimateGasV2`
  - 增加“优先 V2、失败回退旧版”的便捷方法（供 UI 调用）
- `lib/screens/transfer_screen.dart`
  - 转账确认弹窗刷新手续费时（EVM）调用“优先 V2、失败回退旧版”
  - 继续使用 `WalletEstimateGasService.parseGasLimit(data)` 从 `data.gasLimit` 取值

## 数据流与回退策略

1. UI 侧发起估算（EVM）
2. 先请求 `estimateGasV2`
3. 若：
   - 网络/解析失败，或
   - `code != 0`，或
   - `data.gasLimit` 解析失败
   
   则回退请求旧接口 `estimateGas`
4. 最终仍无法得到 gasLimit：按现有逻辑回退到 `21000`

## 非目标

- TRON 的手续费展示仍按当前 UI 逻辑（不展示矿工费），本次不改变其 UI 行为；
  但 V2 接口在 service 层已可被 TRON 侧复用（若未来需要估算/展示）。


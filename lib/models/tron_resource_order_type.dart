/// 波场资源租赁交易类型（与 `GET /trx/resource/price?type=`、`preorder.energyType` 一致）。
abstract final class TronResourceOrderType {
  TronResourceOrderType._();

  /// 笔数套餐
  static const String buyNum = 'buy_num';

  /// 快速租用
  static const String quickRent = 'quick_rent';

  /// 笔数套餐 `preorder.count` 最小值。
  static const int buyNumMinCount = 5;

  /// 快速租用 `preorder.count` 固定值。
  static const int quickRentCount = 1;

  static String priceQueryForMode(bool isBuyNum) =>
      isBuyNum ? buyNum : quickRent;
}

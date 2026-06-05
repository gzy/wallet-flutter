import '../market/app_price_service.dart' show kMarketApiBase;

/// 波场资源 HTTP 路径：**`/api/app/trx/resource/*`**
abstract final class TronResourcePaths {
  TronResourcePaths._();

  static const String _root = '$kMarketApiBase/api/app/trx/resource';

  static Uri detail({required String address}) =>
      Uri.parse('$_root/detail').replace(
        queryParameters: {'address': address.trim()},
      );

  static Uri price({required String type}) =>
      Uri.parse('$_root/price').replace(
        queryParameters: {'type': type.trim()},
      );

  static Uri preorder() => Uri.parse('$_root/preorder');

  static Uri confirmOrder() => Uri.parse('$_root/confirmOrder');
}

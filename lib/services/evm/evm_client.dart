import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../../models/evm_network.dart';
import '../../config/evm_environment.dart';

/// Debug 下把发往节点的 JSON-RPC 打到控制台（`flutter run` 终端 / IDE Debug Console）。
class _DebugLogHttpClient extends http.BaseClient {
  _DebugLogHttpClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    debugPrint('[EVM RPC] ${request.method} ${request.url}');
    if (request is http.Request && request.body.isNotEmpty) {
      final b = request.body;
      debugPrint('[EVM RPC] body: ${b.length > 4000 ? '${b.substring(0, 4000)}…' : b}');
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}

/// 复用的 EVM JSON-RPC 客户端池：每条网络一个 http.Client + Web3Client。
///
/// 这样可以避免频繁创建/销毁 HTTP 连接，提升性能并减少抖动。
class EvmRpcPool {
  EvmRpcPool._();

  static final Map<EvmNetworkId, http.Client> _httpClients = {};
  static final Map<EvmNetworkId, Web3Client> _web3Clients = {};

  static Web3Client client(EvmNetworkId network) {
    final cached = _web3Clients[network];
    if (cached != null) return cached;

    final inner = http.Client();
    final httpClient = kDebugMode ? _DebugLogHttpClient(inner) : inner;
    final web3 = Web3Client(EvmEnvironment.rpcUrl(network), httpClient);
    _httpClients[network] = httpClient;
    _web3Clients[network] = web3;
    return web3;
  }

  /// 释放所有已缓存的客户端（例如 App 退出/测试结束时调用）。
  ///
  /// 注意：Flutter 移动端通常不会有“进程退出回调”，这里更偏向用于测试、
  /// 热重载/热重启期间清理或手动释放。
  static void disposeAll() {
    final clients = _web3Clients.values.toList(growable: false);
    _web3Clients.clear();
    for (final c in clients) {
      // Web3Client.dispose 返回 Future，这里不阻塞调用方（例如 ChangeNotifier.dispose）。
      c.dispose();
    }

    final httpClients = _httpClients.values.toList(growable: false);
    _httpClients.clear();
    for (final h in httpClients) {
      h.close();
    }
  }
}

/// 轻量封装：提供常用 RPC 方法，并复用池内连接。
class EvmRpcClient {
  EvmRpcClient(this.network) : _client = EvmRpcPool.client(network);

  final EvmNetworkId network;
  final Web3Client _client;

  Web3Client get raw => _client;

  Future<EtherAmount> getBalance(EthereumAddress address) => _client.getBalance(address);

  Future<String> getClientVersion() => _client.getClientVersion();
}

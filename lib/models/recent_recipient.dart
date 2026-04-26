/// 最近转账的收款地址（按钱包 + 与后端一致的 `chain` 查询参数分桶展示）。
class RecentRecipient {
  const RecentRecipient({
    required this.address,
    required this.atMs,
  });

  final String address;
  final int atMs;

  Map<String, dynamic> toJson() => {
        'address': address,
        'atMs': atMs,
      };

  factory RecentRecipient.fromJson(Map<String, dynamic> j) {
    return RecentRecipient(
      address: j['address']?.toString() ?? '',
      atMs: (j['atMs'] is int)
          ? j['atMs'] as int
          : int.tryParse(j['atMs']?.toString() ?? '') ?? 0,
    );
  }
}

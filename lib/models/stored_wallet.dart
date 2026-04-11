/// 持久化的钱包元数据（助记词按 [id] 分 key 存储）
class StoredWallet {
  const StoredWallet({
    required this.id,
    required this.name,
    required this.backedUp,
    this.createdAtMs,
  });

  final String id;
  final String name;
  final bool backedUp;

  /// 创建时间（毫秒时间戳）；旧数据无此字段时为 null
  final int? createdAtMs;

  StoredWallet copyWith({String? name, bool? backedUp, int? createdAtMs}) =>
      StoredWallet(
        id: id,
        name: name ?? this.name,
        backedUp: backedUp ?? this.backedUp,
        createdAtMs: createdAtMs ?? this.createdAtMs,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'backedUp': backedUp,
        if (createdAtMs != null) 'createdAtMs': createdAtMs,
      };

  factory StoredWallet.fromJson(Map<String, dynamic> json) {
    return StoredWallet(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Wallet',
      backedUp: json['backedUp'] as bool? ?? false,
      createdAtMs: json['createdAtMs'] as int?,
    );
  }
}

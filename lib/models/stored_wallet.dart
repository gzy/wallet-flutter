/// 持久化的钱包元数据（助记词按 [id] 分 key 存储）
class StoredWallet {
  const StoredWallet({
    required this.id,
    required this.name,
    required this.backedUp,
  });

  final String id;
  final String name;
  final bool backedUp;

  StoredWallet copyWith({String? name, bool? backedUp}) => StoredWallet(
        id: id,
        name: name ?? this.name,
        backedUp: backedUp ?? this.backedUp,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'backedUp': backedUp,
      };

  factory StoredWallet.fromJson(Map<String, dynamic> json) {
    return StoredWallet(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Wallet',
      backedUp: json['backedUp'] as bool? ?? false,
    );
  }
}

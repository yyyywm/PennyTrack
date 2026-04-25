/// 分类数据模型
class Category {
  final int id;
  final String name;
  final String type;
  final String? icon;
  final String? color;
  final int? userId;

  Category({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.color,
    this.userId,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      userId: json['user_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
      'user_id': userId,
    };
  }
}

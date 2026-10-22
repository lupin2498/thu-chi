import 'package:flutter/material.dart';

/// Bộ biểu tượng cố định (dùng khoá chuỗi để lưu DB mà vẫn tree-shake được font).
const Map<String, IconData> kAppIcons = {
  'food': Icons.restaurant,
  'coffee': Icons.local_cafe,
  'market': Icons.shopping_basket,
  'transport': Icons.directions_car,
  'fuel': Icons.local_gas_station,
  'shopping': Icons.shopping_bag,
  'clothes': Icons.checkroom,
  'bill': Icons.receipt_long,
  'electric': Icons.bolt,
  'water': Icons.water_drop,
  'internet': Icons.wifi,
  'phone': Icons.smartphone,
  'home': Icons.home,
  'health': Icons.local_hospital,
  'education': Icons.school,
  'entertainment': Icons.movie,
  'travel': Icons.flight,
  'gift': Icons.card_giftcard,
  'family': Icons.family_restroom,
  'child': Icons.child_care,
  'pet': Icons.pets,
  'beauty': Icons.spa,
  'sport': Icons.fitness_center,
  'invest': Icons.trending_up,
  'loan': Icons.handshake,
  'insurance': Icons.health_and_safety,
  'transfer': Icons.swap_horiz,
  'salary': Icons.payments,
  'bonus': Icons.emoji_events,
  'interest': Icons.percent,
  'sell': Icons.sell,
  'refund': Icons.replay,
  'wallet': Icons.account_balance_wallet,
  'bank': Icons.account_balance,
  'card': Icons.credit_card,
  'savings': Icons.savings,
  'charity': Icons.volunteer_activism,
  'repair': Icons.build,
  'other': Icons.category,
};

IconData appIcon(String? key) => kAppIcons[key] ?? Icons.category;

const List<int> kPalette = [
  0xFFE53935,
  0xFFD81B60,
  0xFF8E24AA,
  0xFF5E35B1,
  0xFF3949AB,
  0xFF1E88E5,
  0xFF039BE5,
  0xFF00ACC1,
  0xFF00897B,
  0xFF43A047,
  0xFF7CB342,
  0xFFC0CA33,
  0xFFFDD835,
  0xFFFFB300,
  0xFFFB8C00,
  0xFFF4511E,
  0xFF6D4C41,
  0xFF757575,
  0xFF546E7A,
];

/// Ô tròn biểu tượng hạng mục / tài khoản.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final String? icon;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(appIcon(icon), color: c, size: size * 0.55),
    );
  }
}

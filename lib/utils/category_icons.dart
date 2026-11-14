import 'package:flutter/material.dart';

/// Icons available for categories. Stored by key (not code point) so Flutter
/// can tree-shake the icon font in release builds.
class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> all = {
    'food': Icons.restaurant_rounded,
    'cafe': Icons.local_cafe_rounded,
    'transport': Icons.directions_car_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'entertainment': Icons.movie_rounded,
    'games': Icons.sports_esports_rounded,
    'bills': Icons.receipt_long_rounded,
    'internet': Icons.wifi_rounded,
    'phone': Icons.phone_android_rounded,
    'home': Icons.home_rounded,
    'health': Icons.favorite_rounded,
    'fitness': Icons.fitness_center_rounded,
    'education': Icons.school_rounded,
    'travel': Icons.flight_rounded,
    'groceries': Icons.local_grocery_store_rounded,
    'pets': Icons.pets_rounded,
    'kids': Icons.child_care_rounded,
    'beauty': Icons.spa_rounded,
    'charity': Icons.volunteer_activism_rounded,
    'salary': Icons.work_rounded,
    'freelance': Icons.laptop_mac_rounded,
    'gift': Icons.card_giftcard_rounded,
    'investment': Icons.trending_up_rounded,
    'refund': Icons.replay_rounded,
    'savings': Icons.savings_rounded,
    'bank': Icons.account_balance_rounded,
    'wallet': Icons.account_balance_wallet_rounded,
    'creditCard': Icons.credit_card_rounded,
    'payments': Icons.payments_rounded,
    'other': Icons.category_rounded,
  };

  static IconData of(String key) => all[key] ?? Icons.category_rounded;

  /// Palette offered when creating a custom category.
  static const List<int> palette = [
    0xFFFF8A65,
    0xFF4FC3F7,
    0xFFF06292,
    0xFFBA68C8,
    0xFFFFD54F,
    0xFFEF5350,
    0xFF7986CB,
    0xFF4DD0E1,
    0xFF81C784,
    0xFF2DD4BF,
    0xFFA78BFA,
    0xFF90A4AE,
  ];
}

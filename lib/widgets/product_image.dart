import 'package:flutter/material.dart';
import '../theme.dart';
import 'food_image.dart';
import 'ui.dart';

/// Do'kon bo'limining ikonkasi va rangi — rasmi yo'q tovarlar uchun
IconData shopIcon(String category) => switch (category) {
      'Forma' => Icons.checkroom_outlined,
      'Anjomlar' => Icons.fitness_center_outlined,
      _ => Icons.local_drink_outlined,
    };

Color shopColor(String category) => switch (category) {
      'Forma' => AppColors.water,
      'Anjomlar' => AppColors.warning,
      _ => AppColors.protein,
    };

/// Tovar rasmi: havola -> nomiga mos ichki rasm (protein, gainer ...) -> bo'lim ikonkasi.
/// Mahsulotlar bazasidagi bilan bir xil qoida ishlatiladi ([FoodImage]).
class ProductImage extends StatelessWidget {
  final String category;
  final String name;
  final String url;
  final double size;
  const ProductImage({
    super.key,
    required this.category,
    this.name = '',
    this.url = '',
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final hasPicture = url.trim().isNotEmpty || foodAsset(name) != null;
    return hasPicture
        ? FoodImage(name: name, url: url, size: size)
        : IconBadge(shopIcon(category), color: shopColor(category), size: size);
  }
}

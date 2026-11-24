import 'package:flutter/material.dart';
import 'app_language.dart';

class BookSourceBadge extends StatelessWidget {
  const BookSourceBadge(this.label, {super.key, this.maxWidth = 72});
  final String label;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    final text = label.trim();
    // 网盘书统一显示“在线阅读”，不再在每张封面上重复贴一枚小标签。
    if (text == '在线阅读' ||
        text.contains('WebDAV') ||
        text.contains('OpenList') ||
        text == '在线') {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AppText(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 9,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

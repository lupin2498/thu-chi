import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'app_icons.dart';

/// Bảng chọn hạng mục dạng lưới.
Future<Category?> pickCategory(
  BuildContext context, {
  required CategoryKind kind,
  int? selectedId,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final cats = ctx.read<AppState>().categoriesOf(kind);
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (ctx, controller) => Column(
          children: [
            Text(
              kind == CategoryKind.income ? 'Chọn mục thu' : 'Chọn mục chi',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 96,
                  mainAxisExtent: 96,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: cats.length,
                itemBuilder: (ctx, i) {
                  final c = cats[i];
                  final selected = c.id == selectedId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, c),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? Theme.of(ctx).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconBadge(icon: c.icon, color: c.color, size: 44),
                          const SizedBox(height: 6),
                          Text(
                            c.name,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Bảng chọn tài khoản.
Future<Account?> pickAccount(
  BuildContext context, {
  int? selectedId,
  int? excludeId,
  String title = 'Chọn tài khoản',
}) {
  return showModalBottomSheet<Account>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final state = ctx.read<AppState>();
      final list = state.accounts.where((a) => a.id != excludeId).toList();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final a in list)
                      ListTile(
                        leading: IconBadge(icon: a.iconKey, color: a.color),
                        title: Text(a.name),
                        subtitle: Text(formatMoney(state.balanceOf(a.id))),
                        trailing: a.id == selectedId
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(ctx).colorScheme.primary,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, a),
                      ),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Chưa có tài khoản khác'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

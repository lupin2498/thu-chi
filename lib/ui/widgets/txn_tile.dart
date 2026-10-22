import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import 'app_icons.dart';
import 'common.dart';

/// Một dòng giao dịch trong danh sách.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, this.onTap, this.showDate = false});

  final TransactionRecord txn;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cat = state.categoryById(txn.categoryId);
    final acc = state.accountById(txn.accountId);
    final toAcc = state.accountById(txn.toAccountId);

    final String title;
    final String icon;
    final int color;
    if (txn.type == TxnType.transfer) {
      title = 'Chuyển khoản';
      icon = 'transfer';
      color = 0xFF1E88E5;
    } else {
      title = cat?.name ?? (txn.type == TxnType.income ? 'Thu khác' : 'Chi khác');
      icon = cat?.icon ?? 'other';
      color = cat?.color ?? 0xFF78909C;
    }

    final subtitleParts = <String>[
      if (txn.note.isNotEmpty) txn.note,
      if (txn.type == TxnType.transfer)
        '${acc?.name ?? '?'} → ${toAcc?.name ?? '?'}'
      else if (acc != null)
        acc.name,
    ];
    final time = showDate
        ? '${formatDate(txn.date)} ${formatTime(txn.date)}'
        : formatTime(txn.date);

    return ListTile(
      onTap: onTap,
      leading: IconBadge(icon: icon, color: color),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (txn.source == TxnSource.auto)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: 'Ghi tự động từ thông báo ngân hàng',
                child: Icon(
                  Icons.bolt,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        [...subtitleParts, time].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: AmountText(txn.amount, type: txn.type),
      ),
    );
  }
}

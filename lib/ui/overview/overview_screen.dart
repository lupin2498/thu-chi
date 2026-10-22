import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../capture/capture_channel.dart';
import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../editor/transaction_editor.dart';
import '../more/auto_capture_screen.dart';
import '../quick_add/quick_add_panel.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/txn_tile.dart';

class OverviewData {
  const OverviewData({
    required this.month,
    required this.byCategory,
    required this.recent,
  });
  final PeriodSummary month;
  final List<CategoryTotal> byCategory;
  final List<TransactionRecord> recent;
}

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  Future<OverviewData>? _future;
  int _rev = -1;
  CapturePermissions? _perm;

  @override
  void initState() {
    super.initState();
    _loadPerm();
  }

  Future<void> _loadPerm() async {
    if (!CaptureChannel.supported) return;
    final p = await CaptureChannel.permissions();
    if (mounted) setState(() => _perm = p);
  }

  Future<OverviewData> _load(AppState s) async {
    final now = DateTime.now();
    final start = monthStart(now);
    final end = nextMonthStart(now);
    return OverviewData(
      month: await s.repo.summary(start, end),
      byCategory: await s.repo.categoryTotals(TxnType.expense, start, end),
      recent: await s.repo.transactions(limit: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_rev != state.revision || _future == null) {
      _rev = state.revision;
      _future = _load(state);
    }
    return RefreshIndicator(
      onRefresh: () async {
        await state.refresh();
        await state.refreshPending();
        await _loadPerm();
      },
      child: FutureBuilder<OverviewData>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _Header(state: state, month: data?.month),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Column(
                  children: [
                    if (state.pending.isNotEmpty) ...[
                      _PendingCard(pending: state.pending),
                      const SizedBox(height: 12),
                    ],
                    if (CaptureChannel.supported &&
                        _perm != null &&
                        !_perm!.ready) ...[
                      _SetupCaptureCard(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AutoCaptureScreen(),
                            ),
                          );
                          _loadPerm();
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    _VoiceCard(),
                    const SizedBox(height: 12),
                    if (state.settings.monthlyBudget > 0 && data != null) ...[
                      _BudgetCard(
                        budget: state.settings.monthlyBudget,
                        spent: data.month.expense,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (data != null) ...[
                      _ExpensePie(totals: data.byCategory),
                      const SizedBox(height: 12),
                      SectionCard(
                        title: 'Ghi chép gần đây',
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                        trailing: TextButton(
                          onPressed: widget.onSeeAll,
                          child: const Text('Xem tất cả'),
                        ),
                        child: data.recent.isEmpty
                            ? const EmptyState(
                                icon: Icons.receipt_long,
                                text: 'Chưa có ghi chép nào.\nBấm + để ghi khoản thu chi đầu tiên.',
                              )
                            : Column(
                                children: [
                                  for (final t in data.recent)
                                    TxnTile(
                                      txn: t,
                                      showDate: true,
                                      onTap: () =>
                                          openEditor(context, existing: t),
                                    ),
                                ],
                              ),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.month});

  final AppState state;
  final PeriodSummary? month;

  @override
  Widget build(BuildContext context) {
    final hidden = state.settings.hideBalance;
    final m = month ?? PeriodSummary.empty;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 12,
        20,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Tổng số dư',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: hidden ? 'Hiện số dư' : 'Ẩn số dư',
                onPressed: () => state.setHideBalance(!hidden),
                icon: Icon(
                  hidden ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                  size: 20,
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hidden ? '••••••••' : formatMoney(state.totalBalance),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            monthLabel(DateTime.now()),
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _HeaderStat(
                  label: 'Thu',
                  value: m.income,
                  icon: Icons.south_west,
                  hidden: hidden,
                ),
              ),
              Expanded(
                child: _HeaderStat(
                  label: 'Chi',
                  value: m.expense,
                  icon: Icons.north_east,
                  hidden: hidden,
                ),
              ),
              Expanded(
                child: _HeaderStat(
                  label: 'Chênh lệch',
                  value: m.net,
                  icon: Icons.balance,
                  hidden: hidden,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.hidden,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            hidden ? '••••' : formatMoney(value),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.pending});

  final List<CaptureData> pending;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return SectionCard(
      title: 'Giao dịch ngân hàng chờ ghi (${pending.length})',
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      trailing: pending.length > 1
          ? TextButton(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Bỏ qua tất cả?',
                  message: 'Các giao dịch chờ sẽ bị xoá khỏi danh sách.',
                  confirm: 'Bỏ qua',
                );
                if (ok) {
                  await CaptureChannel.clearAll();
                  await state.refreshPending();
                }
              },
              child: const Text('Bỏ qua hết'),
            )
          : null,
      child: Column(
        children: [
          for (final c in pending.take(5))
            ListTile(
              leading: IconBadge(
                icon: 'bank',
                color: c.type == TxnType.income ? 0xFF2E7D32 : 0xFFE53935,
              ),
              title: AmountText(c.amount, type: c.type),
              subtitle: Text(
                '${bankLabel(c)} · ${formatDateTime(c.time)}'
                '${c.content != null ? '\n${c.content}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.mic, color: kPrimary),
              onTap: () async {
                await showQuickAddSheet(context, capture: c);
                await state.refreshPending();
              },
            ),
        ],
      ),
    );
  }
}

class _SetupCaptureCard extends StatelessWidget {
  const _SetupCaptureCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(Icons.bolt, color: scheme.onPrimaryContainer, size: 32),
        title: Text(
          'Bật tự động ghi chép',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onPrimaryContainer,
          ),
        ),
        subtitle: Text(
          'Chuyển khoản xong trên MB Bank... là cửa sổ ghi chép hiện ra với số tiền sẵn, chỉ cần nói tên khoản chi.',
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
        onTap: onTap,
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickButton(
            icon: Icons.mic,
            label: 'Nói để ghi',
            color: kPrimary,
            onTap: () => showQuickAddSheet(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickButton(
            icon: Icons.content_paste,
            label: 'Dán SMS/thông báo',
            color: const Color(0xFF00897B),
            onTap: () => pasteBankText(context),
          ),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget, required this.spent});

  final int budget;
  final int spent;

  @override
  Widget build(BuildContext context) {
    final ratio = budget == 0 ? 0.0 : spent / budget;
    final color = ratio >= 1
        ? kExpenseColor
        : ratio >= 0.8
        ? Colors.orange
        : kIncomeColor;
    final now = DateTime.now();
    final daysLeft = daysInMonth(now) - now.day + 1;
    final remain = budget - spent;
    return SectionCard(
      title: 'Hạn mức chi tháng này',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 10,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Đã chi ${formatMoney(spent)} / ${formatMoney(budget)}',
                ),
              ),
              Text('${(ratio * 100).round()}%', style: TextStyle(color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            remain >= 0
                ? 'Còn ${formatMoney(remain)} · khoảng ${formatMoney(remain ~/ daysLeft)}/ngày trong $daysLeft ngày'
                : 'Đã vượt hạn mức ${formatMoney(-remain)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ExpensePie extends StatelessWidget {
  const _ExpensePie({required this.totals});

  final List<CategoryTotal> totals;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sum = totals.fold<int>(0, (a, b) => a + b.total);
    if (sum == 0) {
      return const SectionCard(
        title: 'Chi tiêu tháng này',
        child: EmptyState(
          icon: Icons.pie_chart_outline,
          text: 'Chưa có khoản chi nào trong tháng',
        ),
      );
    }
    final top = totals.take(5).toList();
    final otherTotal = sum - top.fold<int>(0, (a, b) => a + b.total);
    final items = <(String, int, int)>[
      for (final t in top)
        (
          state.categoryById(t.categoryId)?.name ?? 'Không phân loại',
          t.total,
          state.categoryById(t.categoryId)?.color ?? 0xFF9E9E9E,
        ),
      if (otherTotal > 0) ('Khác', otherTotal, 0xFFBDBDBD),
    ];
    return SectionCard(
      title: 'Chi tiêu tháng này',
      child: Row(
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 32,
                sections: [
                  for (final it in items)
                    PieChartSectionData(
                      value: it.$2.toDouble(),
                      color: Color(it.$3),
                      radius: 24,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final it in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Color(it.$3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            it.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '${(it.$2 * 100 / sum).round()}%',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dán nội dung SMS / thông báo ngân hàng từ bộ nhớ tạm để ghi nhanh.
Future<void> pasteBankText(BuildContext context) async {
  final controller = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Dán nội dung SMS / thông báo'),
      content: TextField(
        controller: controller,
        maxLines: 5,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'VD: TK 0xxx|GD: -150,000VND ... |SD: ...|ND: ...',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Phân tích'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final capture = CaptureData.fromText(text);
  if (capture == null) {
    showSnack(context, 'Không tìm thấy số tiền giao dịch trong nội dung này');
    return;
  }
  await showQuickAddSheet(context, capture: capture);
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../transactions/transactions_screen.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Báo cáo'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Chi tiêu'),
              Tab(text: 'Thu nhập'),
              Tab(text: 'Theo tháng'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CategoryReport(type: TxnType.expense),
            _CategoryReport(type: TxnType.income),
            _YearReport(),
          ],
        ),
      ),
    );
  }
}

class _CategoryReport extends StatefulWidget {
  const _CategoryReport({required this.type});

  final TxnType type;

  @override
  State<_CategoryReport> createState() => _CategoryReportState();
}

class _CategoryReportState extends State<_CategoryReport>
    with AutomaticKeepAliveClientMixin {
  DateTime _period = monthStart(DateTime.now());
  bool _yearMode = false;
  Future<List<CategoryTotal>>? _future;
  String _key = '';
  int? _touched;

  DateTime get _start => _yearMode ? DateTime(_period.year) : _period;
  DateTime get _end =>
      _yearMode ? DateTime(_period.year + 1) : nextMonthStart(_period);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final key = '${state.revision}|$_period|$_yearMode';
    if (key != _key || _future == null) {
      _key = key;
      _future = state.repo.categoryTotals(widget.type, _start, _end);
    }
    return FutureBuilder<List<CategoryTotal>>(
      future: _future,
      builder: (context, snap) {
        final totals = snap.data ?? const <CategoryTotal>[];
        final sum = totals.fold<int>(0, (a, b) => a + b.total);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Center(
              child: MonthSwitcher(
                month: _period,
                yearMode: _yearMode,
                onChanged: (m) => setState(() => _period = m),
              ),
            ),
            Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Tháng')),
                  ButtonSegment(value: true, label: Text('Năm')),
                ],
                selected: {_yearMode},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (s) => setState(() {
                  _yearMode = s.first;
                  final now = DateTime.now();
                  if (_yearMode) {
                    _period = DateTime(_period.year);
                  } else {
                    _period = now.year == _period.year
                        ? monthStart(now)
                        : DateTime(_period.year);
                  }
                }),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      widget.type == TxnType.expense ? 'Tổng chi' : 'Tổng thu',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatMoney(sum),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: txnColor(widget.type),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sum == 0)
                      const EmptyState(
                        icon: Icons.pie_chart_outline,
                        text: 'Không có dữ liệu trong kỳ này',
                      )
                    else
                      SizedBox(
                        height: 220,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 50,
                            pieTouchData: PieTouchData(
                              touchCallback: (event, resp) {
                                final idx =
                                    resp?.touchedSection?.touchedSectionIndex;
                                if (!event.isInterestedForInteractions ||
                                    idx == null ||
                                    idx < 0) {
                                  if (_touched != null) {
                                    setState(() => _touched = null);
                                  }
                                  return;
                                }
                                if (idx != _touched) {
                                  setState(() => _touched = idx);
                                }
                              },
                            ),
                            sections: [
                              for (final (i, t) in totals.indexed)
                                PieChartSectionData(
                                  value: t.total.toDouble(),
                                  color: Color(
                                    state.categoryById(t.categoryId)?.color ??
                                        0xFF9E9E9E,
                                  ),
                                  radius: _touched == i ? 62 : 52,
                                  title: t.total * 100 / sum >= 6
                                      ? '${(t.total * 100 / sum).round()}%'
                                      : '',
                                  titleStyle: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (sum > 0)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final t in totals)
                      _CategoryRow(
                        total: t,
                        sum: sum,
                        onTap: () {
                          final cat = state.categoryById(t.categoryId);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TransactionsScreen(
                                categoryId: t.categoryId,
                                type: widget.type,
                                title: cat?.name ?? 'Không phân loại',
                                start: _start,
                                end: _end,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.total,
    required this.sum,
    required this.onTap,
  });

  final CategoryTotal total;
  final int sum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cat = state.categoryById(total.categoryId);
    final ratio = sum == 0 ? 0.0 : total.total / sum;
    final color = Color(cat?.color ?? 0xFF9E9E9E);
    return ListTile(
      onTap: onTap,
      leading: IconBadge(
        icon: cat?.icon ?? 'other',
        color: cat?.color ?? 0xFF9E9E9E,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              cat?.name ?? 'Không phân loại',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatMoney(total.total),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Text(
                '${(ratio * 100).toStringAsFixed(1)}% · ${total.count} lần',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearReport extends StatefulWidget {
  const _YearReport();

  @override
  State<_YearReport> createState() => _YearReportState();
}

class _YearReportState extends State<_YearReport>
    with AutomaticKeepAliveClientMixin {
  int _year = DateTime.now().year;
  Future<List<MonthTotal>>? _future;
  String _key = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = context.watch<AppState>();
    final key = '${state.revision}|$_year';
    if (key != _key || _future == null) {
      _key = key;
      _future = state.repo.monthTotals(_year);
    }
    return FutureBuilder<List<MonthTotal>>(
      future: _future,
      builder: (context, snap) {
        final months = snap.data ?? const <MonthTotal>[];
        final income = months.fold<int>(0, (a, b) => a + b.income);
        final expense = months.fold<int>(0, (a, b) => a + b.expense);
        var maxY = 0;
        for (final m in months) {
          if (m.income > maxY) maxY = m.income;
          if (m.expense > maxY) maxY = m.expense;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Center(
              child: MonthSwitcher(
                month: DateTime(_year),
                yearMode: true,
                onChanged: (m) => setState(() => _year = m.year),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Legend(
                          color: kIncomeColor,
                          label: 'Thu ${formatCompact(income)}',
                        ),
                        const SizedBox(width: 16),
                        _Legend(
                          color: kExpenseColor,
                          label: 'Chi ${formatCompact(expense)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 240,
                      child: maxY == 0
                          ? const EmptyState(
                              icon: Icons.bar_chart,
                              text: 'Chưa có dữ liệu năm này',
                            )
                          : BarChart(
                              BarChartData(
                                maxY: maxY * 1.15,
                                gridData: const FlGridData(
                                  drawVerticalLine: false,
                                ),
                                borderData: FlBorderData(show: false),
                                barTouchData: BarTouchData(
                                  touchTooltipData: BarTouchTooltipData(
                                    getTooltipItem: (group, gi, rod, ri) =>
                                        BarTooltipItem(
                                          '${ri == 0 ? 'Thu' : 'Chi'} T${group.x + 1}\n${formatMoney(rod.toY.round())}',
                                          const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                  ),
                                ),
                                titlesData: FlTitlesData(
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 44,
                                      getTitlesWidget: (v, meta) =>
                                          SideTitleWidget(
                                            meta: meta,
                                            child: Text(
                                              formatCompact(v.round()),
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (v, meta) =>
                                          SideTitleWidget(
                                            meta: meta,
                                            child: Text(
                                              '${v.toInt() + 1}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                                barGroups: [
                                  for (final (i, m) in months.indexed)
                                    BarChartGroupData(
                                      x: i,
                                      barsSpace: 2,
                                      barRods: [
                                        BarChartRodData(
                                          toY: m.income.toDouble(),
                                          color: kIncomeColor,
                                          width: 7,
                                        ),
                                        BarChartRodData(
                                          toY: m.expense.toDouble(),
                                          color: kExpenseColor,
                                          width: 7,
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    title: const Text(
                      'Tháng',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: SizedBox(
                      width: 200,
                      child: Row(
                        children: const [
                          Expanded(
                            child: Text('Thu', textAlign: TextAlign.end),
                          ),
                          Expanded(
                            child: Text('Chi', textAlign: TextAlign.end),
                          ),
                          Expanded(
                            child: Text('Còn lại', textAlign: TextAlign.end),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final m in months)
                    if (m.income > 0 || m.expense > 0)
                      ListTile(
                        dense: true,
                        title: Text('Tháng ${m.month.month}'),
                        trailing: SizedBox(
                          width: 200,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  formatCompact(m.income),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(color: kIncomeColor),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  formatCompact(m.expense),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(color: kExpenseColor),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  formatCompact(m.income - m.expense),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

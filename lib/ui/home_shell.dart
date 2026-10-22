import 'package:flutter/material.dart';

import 'editor/transaction_editor.dart';
import 'more/more_screen.dart';
import 'overview/overview_screen.dart';
import 'quick_add/quick_add_panel.dart';
import 'reports/reports_screen.dart';
import 'transactions/transactions_screen.dart';

/// Khung chính: 4 tab + nút Ghi chép ở giữa (giống bố cục sổ thu chi quen thuộc).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;

  void selectTab(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      OverviewScreen(onSeeAll: () => selectTab(1)),
      const TransactionsScreen(),
      const ReportsScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: GestureDetector(
        onLongPress: () => showQuickAddSheet(context),
        child: FloatingActionButton(
          key: const Key('fab_add'),
          tooltip: 'Ghi chép (giữ để nói)',
          shape: const CircleBorder(),
          onPressed: () => openEditor(context),
          child: const Icon(Icons.add, size: 30),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        height: 64,
        child: Row(
          children: [
            _NavItem(icon: Icons.home_outlined, active: Icons.home, label: 'Tổng quan', selected: _index == 0, onTap: () => selectTab(0)),
            _NavItem(icon: Icons.receipt_long_outlined, active: Icons.receipt_long, label: 'Sổ giao dịch', selected: _index == 1, onTap: () => selectTab(1)),
            const SizedBox(width: 72),
            _NavItem(icon: Icons.pie_chart_outline, active: Icons.pie_chart, label: 'Báo cáo', selected: _index == 2, onTap: () => selectTab(2)),
            _NavItem(icon: Icons.more_horiz, active: Icons.more_horiz, label: 'Khác', selected: _index == 3, onTap: () => selectTab(3)),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.active,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData active;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkResponse(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? active : icon, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: color, fontWeight: selected ? FontWeight.w600 : null),
            ),
          ],
        ),
      ),
    );
  }
}

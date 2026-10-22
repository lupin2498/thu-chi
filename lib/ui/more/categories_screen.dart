import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'accounts_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Hạng mục thu chi'),
            bottom: const TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                Tab(text: 'Mục chi'),
                Tab(text: 'Mục thu'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Thêm hạng mục',
            onPressed: () {
              final idx = DefaultTabController.of(context).index;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryEditor(
                    kind: idx == 0 ? CategoryKind.expense : CategoryKind.income,
                  ),
                ),
              );
            },
            child: const Icon(Icons.add),
          ),
          body: const TabBarView(
            children: [
              _CategoryList(kind: CategoryKind.expense),
              _CategoryList(kind: CategoryKind.income),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.kind});

  final CategoryKind kind;

  @override
  Widget build(BuildContext context) {
    final list = context.watch<AppState>().categoriesOf(kind);
    if (list.isEmpty) {
      return const EmptyState(icon: Icons.category, text: 'Chưa có hạng mục');
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final c = list[i];
        return ListTile(
          leading: IconBadge(icon: c.icon, color: c.color),
          title: Text(c.name),
          trailing: const Icon(Icons.edit_outlined, size: 20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CategoryEditor(kind: kind, category: c),
            ),
          ),
        );
      },
    );
  }
}

class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, required this.kind, this.category});

  final CategoryKind kind;
  final Category? category;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final _nameCtrl = TextEditingController();
  late String _icon;
  late int _color;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _nameCtrl.text = c?.name ?? '';
    _icon = c?.icon ?? 'other';
    _color = c?.color ?? kPalette[0];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showSnack(context, 'Nhập tên hạng mục');
      return;
    }
    final c = widget.category;
    await context.read<AppState>().saveCategory(
      Category(
        id: c?.id,
        name: name,
        kind: widget.kind,
        icon: _icon,
        color: _color,
        sortOrder: c?.sortOrder ?? 0,
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final c = widget.category;
    if (c?.id == null) return;
    final ok = await confirmDialog(
      context,
      title: 'Xoá hạng mục "${c!.name}"?',
      message:
          'Nếu hạng mục đã được dùng, nó sẽ được ẩn để giữ lịch sử giao dịch.',
      confirm: 'Xoá',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final removed = await context.read<AppState>().deleteCategory(c.id!);
    if (!mounted) return;
    showSnack(context, removed ? 'Đã xoá hạng mục' : 'Đã ẩn hạng mục');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category == null ? 'Thêm hạng mục' : 'Sửa hạng mục'),
        actions: [
          if (widget.category != null)
            IconButton(
              tooltip: 'Xoá',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconBadge(icon: _icon, color: _color, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  autofocus: widget.category == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: widget.kind == CategoryKind.expense
                        ? 'Tên mục chi'
                        : 'Tên mục thu',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Biểu tượng'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kAppIcons.entries)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _icon = e.key),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: e.key == _icon
                            ? Color(_color)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: IconBadge(icon: e.key, color: _color, size: 40),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Màu'),
          const SizedBox(height: 8),
          ColorPickerRow(
            value: _color,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _save,
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

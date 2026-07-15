import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';

/// 信号日志页面 —— 紧凑通知流视图。
class SignalLogPage extends StatefulWidget {
  const SignalLogPage({super.key});

  @override
  State<SignalLogPage> createState() => _SignalLogPageState();
}

class _SignalLogPageState extends State<SignalLogPage> {
  List<UserSignal> _signals = [];
  bool _loading = true;
  String _range = '7d';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final store = SumiScope.read(context);
      final db = store.signalDb;
      debugPrint('[SignalLogPage] signalDb is null? ${db == null}');
      debugPrint('[SignalLogPage] signalService is null? ${store.signalService == null}');
      if (db == null) {
        debugPrint('[SignalLogPage] ❌ signalDb 为 null，无法查询');
        if (mounted) setState(() => _loading = false);
        return;
      }
      final signals = await db.query(type: null, range: _range, limit: 100);
      debugPrint('[SignalLogPage] 查询结果: ${signals.length} 条信号 (range=$_range)');
      if (mounted) setState(() { _signals = signals; _loading = false; });
    } catch (e, stack) {
      debugPrint('[SignalLogPage] ❌ 查询异常: $e');
      debugPrint('[SignalLogPage] 堆栈: $stack');
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _typeLabels = {
    SignalType.todoCreated: '创建了',
    SignalType.todoCompleted: '完成了',
    SignalType.todoUncompleted: '取消完成',
    SignalType.todoDeleted: '删除了',
    SignalType.todoEdited: '编辑了',
    SignalType.todoMovedDate: '移动了',
    SignalType.projectGoalSet: '设定了项目目标',
    SignalType.projectLevelSet: '调整了项目水平',
    SignalType.projectCycleSet: '修改了项目周期',
    SignalType.projectTimeSet: '调整了时间投入',
  };

  /// 每种信号类型对应的颜色。
  static const _typeColors = {
    SignalType.todoCreated: Color(0xFF8894FF),
    SignalType.todoCompleted: Color(0xFF15A877),
    SignalType.todoUncompleted: Color(0xFF737373),
    SignalType.todoDeleted: Color(0xFFE8463A),
    SignalType.todoEdited: Color(0xFF2F74FF),
    SignalType.todoMovedDate: Color(0xFF9B7DFF),
    SignalType.projectGoalSet: Color(0xFFEA9D34),
    SignalType.projectLevelSet: Color(0xFF00B6F5),
    SignalType.projectCycleSet: Color(0xFF9570FF),
    SignalType.projectTimeSet: Color(0xFF5FC000),
  };

  Color _iconColorFor(SignalType s) => _typeColors[s] ?? primary500;

  /// 格式化时间为相对时间（今天/昨天/X月X日）。
  String _formatDate(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final signalDay = DateTime(t.year, t.month, t.day);

    if (signalDay == today) return '今天';
    if (signalDay == yesterday) return '昨天';
    return '${t.month}月${t.day}日';
  }

  /// 格式化时间为 HH:mm。
  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// 按日期分组信号。
  Map<String, List<UserSignal>> _groupByDate() {
    final map = <String, List<UserSignal>>{};
    for (final s in _signals) {
      final key = _formatDate(s.time);
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  /// 构建扁平列表数据源（日期标题 + 信号行交替）。
  List<Object> _buildFlatItems() {
    final groups = _groupByDate();
    final items = <Object>[];
    for (final entry in groups.entries) {
      items.add(_DateHeader(entry.key));
      for (final signal in entry.value) {
        items.add(_SignalItem(signal));
      }
    }
    return items;
  }

  /// 信号描述文本。
  String _signalDesc(UserSignal s) {
    final ctx = s.context;
    final title = ctx['title'] is String ? (ctx['title'] as String?) ?? '' : '';
    final action = _typeLabels[s.signal] ?? s.signal.name;
    if (title.isNotEmpty) return '$action「$title」';
    return action;
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildFlatItems();

    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(s16, s8, s16, s12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text('信号日志',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ink)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: s10, vertical: s4),
                    decoration: BoxDecoration(
                      color: surfaceChip,
                      borderRadius: BorderRadius.circular(radiusPill),
                    ),
                    child: Text('${_signals.length} 条',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: textTertiary)),
                  ),
                ],
              ),
            ),
            // 时间范围 filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: s16),
              child: Row(
                children: ['7d', '30d', 'all'].map((r) {
                  final active = _range == r;
                  return Padding(
                    padding: const EdgeInsets.only(right: s6),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _range = r);
                        _load();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(horizontal: s12, vertical: s6),
                        decoration: BoxDecoration(
                          color: active ? primary500 : surfaceChip,
                          borderRadius: BorderRadius.circular(radiusPill),
                        ),
                        child: Text(
                          r == 'all' ? '全部' : '${r == "30d" ? "30" : "7"} 天',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                            color: active ? Colors.white : textTertiary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: s8),
            // Signal list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _signals.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(s16, s4, s16, s24),
                          itemCount: items.length,
                          separatorBuilder: (_, i) {
                            if (items[i] is _SignalItem &&
                                i + 1 < items.length &&
                                items[i + 1] is _SignalItem) {
                              return const Divider(height: 1, thickness: 0.5, indent: s20);
                            }
                            return const SizedBox.shrink();
                          },
                          itemBuilder: (_, i) {
                            final item = items[i];
                            if (item is _DateHeader) return _buildDateHeader(item.label);
                            if (item is _SignalItem) return _buildSignalRow(item.signal);
                            return const SizedBox.shrink();
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: s14, bottom: s6),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textTertiary),
      ),
    );
  }

  Widget _buildSignalRow(UserSignal s) {
    final desc = _signalDesc(s);
    final color = _iconColorFor(s.signal);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: s8),
      child: Row(
        children: [
          // 彩色圆点
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: s10),
          // 描述
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: ink, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: s8),
          // 时间
          Text(_formatTime(s.time),
              style: const TextStyle(fontSize: 12, color: textTertiary)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: textTertiary.withValues(alpha: 0.4)),
          const SizedBox(height: s12),
          const Text('暂无信号记录',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textTertiary)),
          const SizedBox(height: s4),
          const Text('操作事项和项目时会产生信号',
              style: TextStyle(fontSize: 12, color: textTertiary)),
        ],
      ),
    );
  }
}

/// 日期分组标题。
class _DateHeader {
  final String label;
  const _DateHeader(this.label);
}

/// 扁平列表中的信号条目。
class _SignalItem {
  final UserSignal signal;
  const _SignalItem(this.signal);
}

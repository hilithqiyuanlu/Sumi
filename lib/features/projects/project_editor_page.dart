import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/models.dart';
import '../../sumi_scope.dart';
import '../../theme/app_theme.dart';
import 'assessment_loading_page.dart';

/// 全屏项目编辑页（06 轮：替代弹窗式 project_editor）。
class ProjectEditorPage extends StatefulWidget {
  final Project? project; // null = 新建模式

  const ProjectEditorPage({this.project, super.key});

  @override
  State<ProjectEditorPage> createState() => _ProjectEditorPageState();
}

class _ProjectEditorPageState extends State<ProjectEditorPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _goalCtrl;
  late final TextEditingController _levelCtrl;

  late ProjectColor _color;
  late int _cycleMonths;
  late int _timeConstraint;

  bool get _isEditing => widget.project != null;

  static const _cycleLabels = [
    '1 个月', '2 个月', '3 个月', '4 个月', '5 个月',
    '6 个月', '7 个月', '8 个月', '9 个月', '10 个月', '11 个月',
    '1 年', '1.5 年', '2 年', '1 坤年',
  ];
  static const _cycleValues = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 18, 24, 30,
  ];

  static const _hourLabels = [
    '6 小时', '10 小时', '15 小时', '20 小时',
    '30 小时', '40 小时', '50 小时', '60 小时', '70 小时',
  ];
  static const _hourValues = [6, 10, 15, 20, 30, 40, 50, 60, 70];

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _goalCtrl = TextEditingController(text: p?.goal ?? '');
    _levelCtrl = TextEditingController(text: p?.level ?? '');
    _color = p?.color ?? SumiScope.read(context).nextAvailableColor();
    _cycleMonths = p?.cycleMonths ?? 3;
    if (!_cycleValues.contains(_cycleMonths)) _cycleMonths = _cycleValues.first;

    _timeConstraint = p?.timeConstraint ?? 0;
    if (!_hourValues.contains(_timeConstraint)) _timeConstraint = _hourValues.first;

    // 监听目标输入以更新按钮状态
    _goalCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _goalCtrl.dispose();
    _levelCtrl.dispose();
    super.dispose();
  }

  /// 编辑模式下判断是否仅修改了名称（名称变更不触发重新规划）。
  bool get _onlyNameChanged {
    if (!_isEditing) return false;
    final p = widget.project!;
    final goal = _goalCtrl.text.trim();
    final level = _levelCtrl.text.trim();
    return goal == p.goal &&
        level == p.level &&
        _cycleMonths == p.cycleMonths &&
        _timeConstraint == p.timeConstraint &&
        _color == p.color;
  }

  void _submit() {
    final goal = _goalCtrl.text.trim();
    if (goal.isEmpty) return;

    final store = SumiScope.read(context);
    final name = _nameCtrl.text.trim().isEmpty
        ? (_isEditing ? (widget.project?.name ?? '未命名项目') : '未命名项目')
        : _nameCtrl.text.trim();

    String projectId;
    if (_isEditing) {
      projectId = widget.project!.id;
      store.updateProject(
        projectId,
        name: name,
        color: _color,
        goal: goal,
        level: _levelCtrl.text.trim(),
        cycleMonths: _cycleMonths,
        timeConstraint: _timeConstraint,
      );

      // 仅改名 → 直接保存并返回，不重新评估
      if (_onlyNameChanged) {
        Navigator.of(context).pop();
        return;
      }
    } else {
      // 新建：创建空壳项目（不含月卡，等规划完成后一次性写入）
      projectId = store.addProjectDraft(
        name: name,
        color: _color,
        goal: goal,
        level: _levelCtrl.text.trim(),
        cycleMonths: _cycleMonths,
        timeConstraint: _timeConstraint,
      );
    }

    // 进入评估流程
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssessmentLoadingPage(
          projectId: projectId,
          goal: goal,
          level: _levelCtrl.text.trim(),
          cycleMonths: _cycleMonths,
          timeConstraint: _timeConstraint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(s20, topPadding + 56 + s8, s20, s20),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名称
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '项目名称',
                    hintText: '未命名项目',
                  ),
                ),
                const SizedBox(height: s16),

                // 颜色选择
                const Text('颜色',
                    style: TextStyle(fontSize: 13, color: textTertiary)),
                const SizedBox(height: s8),
                Wrap(
                  spacing: s6,
                  runSpacing: s6,
                  children: ProjectColor.values.map((c) {
                    final selected = c == _color;
                    final fill = projectFillColor(c);
                    return GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: fill,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? mintDeep : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: s16),

                // 目标（必填）
                TextField(
                  controller: _goalCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '目标 *',
                    hintText: '描述你的学习目标',
                  ),
                ),
                const SizedBox(height: s16),

                // 水平
                TextField(
                  controller: _levelCtrl,
                  decoration: const InputDecoration(
                    labelText: '当前水平',
                    hintText: '如：零基础 / 入门 / 进阶',
                  ),
                ),
                const SizedBox(height: s16),

                // 周期 + 投入时间并排
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PickerColumn<int>(
                        label: '周期',
                        value: _cycleMonths,
                        items: _cycleValues,
                        labels: _cycleLabels,
                        onChanged: (v) => setState(() => _cycleMonths = v),
                      ),
                    ),
                    const SizedBox(width: s12),
                    Expanded(
                      child: _PickerColumn<int>(
                        label: '投入时间/周',
                        value: _timeConstraint,
                        items: _hourValues,
                        labels: _hourLabels,
                        onChanged: (v) => setState(() => _timeConstraint = v),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: s32),

                // 提交按钮
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _goalCtrl.text.trim().isEmpty ? null : _submit,
                    child: const Text('保存项目'),
                  ),
                ),
                const SizedBox(height: s8),
                Center(
                  child: Text(
                    '填写目标后，Sumi 将评估可行性并生成学习计划',
                    style: const TextStyle(fontSize: 12, color: textTertiary),
                  ),
                ),
              ],
              ),
            ),
          ),
          // 顶部渐变遮罩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 56,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.white.withValues(alpha: 0.92),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // 关闭按钮 + 标题
          Positioned(
            top: topPadding,
            left: 4,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  _isEditing ? '编辑项目' : '新建项目',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 滚轮选择器列。从 project_editor.dart 提取为公共组件。
class _PickerColumn<T> extends StatefulWidget {
  final String label;
  final T value;
  final List<T> items;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  const _PickerColumn({
    required this.label,
    required this.value,
    required this.items,
    required this.labels,
    required this.onChanged,
  });

  @override
  State<_PickerColumn<T>> createState() => _PickerColumnState<T>();
}

class _PickerColumnState<T> extends State<_PickerColumn<T>> {
  late final FixedExtentScrollController _wheelCtrl;

  @override
  void initState() {
    super.initState();
    final idx = widget.items.indexOf(widget.value);
    _wheelCtrl = FixedExtentScrollController(initialItem: idx >= 0 ? idx : 0);
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.label,
            style: const TextStyle(fontSize: 13, color: textTertiary)),
        const SizedBox(height: s6),
        SizedBox(
          height: 120,
          child: Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: mintDeep.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(s8),
                    ),
                  ),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: _wheelCtrl,
                itemExtent: 36,
                diameterRatio: 2.5,
                perspective: 0.005,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (index) {
                  HapticFeedback.selectionClick();
                  if (index >= 0 && index < widget.items.length) {
                    widget.onChanged(widget.items[index]);
                  }
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  builder: (context, index) {
                    final label = widget.labels[index];
                    final selected = widget.items[index] == widget.value;
                    return Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: selected ? 17 : 15,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? mintDeep : textTertiary,
                        ),
                      ),
                    );
                  },
                  childCount: widget.items.length,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}



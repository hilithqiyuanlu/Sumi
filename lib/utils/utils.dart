/// 日期与 ID 工具函数。

const _toolNameMap = {
  'search_web': '搜索',
  'read_memory': '读取记忆',
  'write_memory': '写入记忆',
  'read_todos': '查看事项',
  'write_todo': '创建事项',
};

/// 工具名称 → 中文标签。
String toolDisplayName(String name) => _toolNameMap[name] ?? name;

DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dateKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

String newSumiId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

/// 日期与 ID 工具函数。

DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dateKey(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

String newSumiId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

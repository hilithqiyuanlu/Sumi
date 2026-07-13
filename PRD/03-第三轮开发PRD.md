# Sumi 03 轮开发 PRD — Todo 体验升级 + 日历联动 + Streaming

## 概述

01 轮有了基础壳（事项/设置、日历、项目系统），02 轮打通了 DeepSeek API（>16 字拆分）。但事项首页离 Google Keep 体验差距大：布局是 Wrap 凑合的、无 pin/done 交互、无拖拽、无日历筛选、无编辑面板、API 调用全是阻塞式。

03 轮目标：把 Todo 体验做到位，一次到位。

---

## 1. 模型变更

### TodoItem 新增字段 (models.dart)

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `pinned` | `bool` | `false` | 置顶标记 |
| `sortOrder` | `int` | `0` | 手动排序序号（越大越靠前） |
| `reminderTime` | `String?` | `null` | 提醒时间 "HH:mm" 格式 |

`date` 字段已存在（`String?`），本次启用：用于存储用户分配的日期（ISO8601），拖到某天即写入该字段。`null` 表示未分配日期（显示在全部事项中）。

### copyWith / toJson / fromJson 同步更新
- `copyWith` 增加 `pinned`, `sortOrder`, `reminderTime`, `date` 参数
- 序列化/反序列化覆盖新字段

---

## 2. AiService 变更

### 2.1 新增 `polishTodo` 方法

```
POST https://api.deepseek.com/v1/chat/completions
model: deepseek-chat
非流式（polish 返回短文本，streaming 收益不大）
```

System prompt：
```
你是 Sumi（米糖），一个个人助手。你的任务是优化用户提供的 todo 标题。
要求：凝练清晰、保留原意、2-20 字、只返回优化后的文本，不要加引号或额外文字。
```

### 2.2 新增 `streamChat` 方法

```
POST https://api.deepseek.com/v1/chat/completions
model: deepseek-chat
stream: true
```

返回 `Stream<String>`（逐 chunk 的 delta content）。使用 `http.Client.send()` 获取 `StreamedResponse`，按行解析 SSE（`data: {...}` → JSON → `choices[0].delta.content`）。

- polish 用非流式（返回文本短），`streamChat` 作为预留能力，用于后续米糖 Tab 对话

---

## 3. Store 变更

### 3.1 sumi_store_todos.dart 新增方法

```dart
// Pin
void togglePin(String id)

// 日期
void updateTodoDate(String id, String? date)  // null = 移除日期

// 项目归属
void updateTodoProject(String id, String? projectId)

// 提醒
void updateTodoReminder(String id, String? reminderTime)

// 排序：交换两个 todo 的 sortOrder
void reorderTodos(String draggedId, String targetId)

// AI 润色
Future<String?> polishTodoTitle(String id)  // 返回 null = 失败
```

### 3.2 排序与筛选 getter

```dart
/// 用于展示的排序列表：
/// 1. pinned（sortOrder 降序）
/// 2. 未完成（sortOrder 降序）
/// 3. 已完成（sortOrder 降序）
List<TodoItem> get sortedTodos { ... }

/// 当前选中日期的 todo（date == null 的视为"未分配日期"，始终显示）
List<TodoItem> get todosForSelectedDate { ... }
```

### 3.3 新增 todo 时自动赋值 sortOrder

`addUserTodo` / `addSystemTodo` 创建时，`sortOrder` 设为当前最大 sortOrder + 1。

---

## 4. 新增 pub 依赖

```yaml
flutter_staggered_grid_view: ^0.7.0  # MasonryGridView
```

注：不用 `ReorderableListView` —— masonry + reorder 自己实现（LongPressDraggable + DragTarget）。

---

## 5. UI 层改动

### 5.1 TodoGrid 重写 — MasonryGridView

- 替换 `Wrap` + `_TodoWrap` → `MasonryGridView.count`（crossAxisCount: 2）
- 数据源从 `store.userTodos` / `store.systemTodos` 改为 `store.sortedTodos`（合并，不再分区）
- 每个 item 估算高度：根据 title 长度计算 `mainAxisExtent`（短 ~80, 中 ~120, 长 ~160）+ 项目归属行
- 支持日期筛选：`store.todosForSelectedDate`

### 5.2 TodoCard 重构 — 新增 pin / done 交互

```
┌──────────────────────────────┐
│ [✓/○]  Title text     [📌]  │  ← 第一行
│        项目名称 (若归属)      │  ← 第二行（仅归属项目时）
│        🕐 HH:mm (若有提醒)    │  ← 第三行（仅设置提醒时）
└──────────────────────────────┘
```

- **左上角**：`GestureDetector` 区域，点击切换 done（`store.toggleTodo`），显示 ✓（已完成，mintDeep）或 ○（未完成，line）
- **右上角**：`GestureDetector` 区域，点击切换 pin（`store.togglePin`），显示 📌 实心/空心
- **卡片主体文本区**：点击 → 打开编辑面板（`TodoEditSheet`）
- **长按**：进入拖拽模式（`LongPressDraggable`）
- done 的卡片：文字变灰 + 删除线，整体透明度降低
- pinned 的卡片：右上角 pin 图标高亮

### 5.3 拖拽系统 — LongPressDraggable + DragTarget

**架构**：
- 每个 `TodoCard` 外层包裹 `LongPressDraggable<TodoItem>`（data = todo）
- 每个 masonry cell 同时包裹 `DragTarget<TodoItem>`（用于 reorder）
- `DateStrip` 中每个 `_DateChip` 包裹 `DragTarget<TodoItem>`（用于日期分配）

**行为**：
- 拖拽中：原位置显示半透明占位，被拖卡片跟随手指（带 elevation 阴影）
- 拖到另一个 card 上松手 → 交换 sortOrder（`store.reorderTodos`）
- 拖到 DateStrip 的某个日期 chip 上：
  - 该日期 < 今天 → chip 变淡红（`Colors.red.shade100`），松手 toast「不能拖到过去的日期」
  - 该日期 >= 今天 → chip 高亮，松手调用 `store.updateTodoDate(todo.id, dateKey(date))`
- 拖到网格空白区 → 取消拖拽，卡片回原位

### 5.4 新增 TodoEditSheet — 编辑面板

底部弹出面板：

```
┌─────────────────────────────────┐
│  [拖拽把手]                      │
│                                  │
│  ┌─────────────────────────┐    │
│  │ TextField (编辑标题)      │    │
│  └─────────────────────────┘    │
│                                  │
│  [润色] [项目] [定时] [复制]     │  ← 四个操作按钮
│                                  │
│  ┌─ 润色结果预览（若触发）────┐  │
│  │ "凝练后的文本..."           │  │
│  │ [应用] [重试]               │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌─ 项目选择（若展开）─────────┐ │
│  │ ○ 无项目（白色）             │ │
│  │ ○ 项目A (lemon)             │ │
│  │ ○ 项目B (mint)              │ │
│  └────────────────────────────┘  │
└─────────────────────────────────┘
```

**四个按钮行为**：
| 按钮 | 图标 | 行为 |
|------|------|------|
| 润色 | `Icons.auto_fix_high_rounded` | 调用 `store.polishTodoTitle(id)`，loading 态，结果预览 + 应用/重试 |
| 项目 | `Icons.folder_rounded` | 展开/收起项目列表（无项目 + 已有项目），选中即更新 |
| 定时 | `Icons.timer_rounded` | 弹出 `TimePickerDialog`，选完更新 `reminderTime` |
| 复制 | `Icons.copy_rounded` | `Clipboard.setData`，toast「已复制」 |

**润色流程**：
1. 点击润色 → 按钮变 loading
2. `store.polishTodoTitle(id)` → DeepSeek API
3. 成功 → 显示预览（原文字 vs 润色后），可[应用]或[重试]
4. 失败 → toast「润色失败，请重试」

### 5.5 DateStrip 改造 — DragTarget + 日期筛选联动

- 每个 `_DateChip` 包裹 `_DraggableDateChip`（DragTarget<TodoItem>）
- `onWillAcceptWithDetails`：始终返回 true
- `onAcceptWithDetails`：过去日期 toast 红色反馈，今天及未来直接分配日期
- 底部拖拽把手保持不变（展开月视图）
- `selectedDate` 已在 store 中，`TodoGrid` 通过 `store.todosForSelectedDate` 响应

---

## 6. 文件清单

### 修改文件（8 个）

| 文件 | 改动 |
|------|------|
| `lib/models/models.dart` | TodoItem +pinned +sortOrder +reminderTime，更新 copyWith/toJson/fromJson |
| `lib/services/ai_service.dart` | +polishTodo(), +streamChat() |
| `lib/store/sumi_store_todos.dart` | +togglePin, +updateTodoDate, +updateTodoProject, +updateTodoReminder, +reorderTodos, +polishTodoTitle, +sortedTodos, +todosForSelectedDate |
| `lib/store/sumi_store.dart` | +aiService getter |
| `lib/features/todos/todo_grid.dart` | 完全重写：Wrap → MasonryGridView, 合并用户/系统分区, 日期筛选, DragTarget 包裹 |
| `lib/features/todos/todo_card.dart` | 完全重写：+pin 图标, +done 图标, +项目归属行, +提醒行, LongPressDraggable 包裹, 分区点击 |
| `lib/features/calendar/date_strip.dart` | _DateChip 加 DragTarget, 过去日期 hover 红色反馈 |
| `pubspec.yaml` | +flutter_staggered_grid_view |

### 新增文件（1 个）

| 文件 | 说明 |
|------|------|
| `lib/features/todos/todo_edit_sheet.dart` | 编辑面板：TextField + 润色/项目/定时/复制 四个功能 |

---

## 7. 实施顺序

```
Phase 1: 数据层
  1. models.dart — TodoItem 新字段 + copyWith/toJson/fromJson
  2. sumi_store_todos.dart + sumi_store.dart — 新 mutation 方法 + sortedTodos

Phase 2: API 层
  3. ai_service.dart — polishTodo + streamChat

Phase 3: UI 核心 + 新增依赖
  4. pubspec.yaml + flutter pub get
  5. todo_card.dart — 完全重写（pin/done 交互 + 分区点击 + LongPressDraggable）
  6. todo_grid.dart — 完全重写（MasonryGridView + 日期筛选 + DragTarget）

Phase 4: 拖拽 + 编辑
  7. date_strip.dart — _DateChip DragTarget + 过去日期红色反馈
  8. todo_edit_sheet.dart — 新增编辑面板

Phase 5: 收尾
  9. flutter analyze 验证零错误
 10. 手动测试关键路径
```

---

## 8. 风险与降级

| 风险 | 降级方案 |
|------|----------|
| `flutter_staggered_grid_view` masonry 拖拽不稳定 | 回退到 Wrap + 简化的 DragTarget 排序 |
| 拖拽到 DateStrip 的命中检测不准 | 先只做 DateStrip 整体 DragTarget，取第一个 hover 日期 |
| Streaming (SSE) 解析复杂 | polish 用非流式做，streamChat 作为独立方法不影响主流程 |

---

## 9. 验证清单

- [ ] TodoItem 新字段序列化/反序列化正确（冷启动数据不丢失）
- [ ] 已 pin 的 todo 置顶，已完成 todo 沉底
- [ ] 点击左上角切换 done，点击右上角切换 pin
- [ ] 点击卡片正文 → 编辑面板弹出
- [ ] 编辑面板：润色可调用 AI 并返回结果、项目归属可切换、定时可设置、复制可复制
- [ ] 长按拖拽 → 拖到另一卡片 → reorder
- [ ] 长按拖拽 → 拖到未来日期 → todo 分配到该日期
- [ ] 长按拖拽 → 拖到过去日期 → 红色反馈 + toast
- [ ] 日期筛选：选中日期只显示该日 todo（含未分配日期的）
- [ ] Masonry 布局：卡片两端对齐，不同高度自然排列
- [ ] 退出编辑面板后网格排序刷新正确
- [ ] flutter analyze 零错误

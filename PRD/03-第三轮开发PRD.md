# 03 — Sumi（米糖）第三轮开发 PRD

> **版本**：v1.0 · 2026-07-14  
> **本轮目标**：Todo 体验对齐 Google Keep，打通日历联动，支持 streaming。  
> **不做**：米糖 Tab 对话、项目 AI 规划、本地推送提醒。

---

## 1. 与第二轮的衔接

| 02 已交付 | 03 改动 |
|-----------|---------|
| Wrap 凑合网格 | **→ MasonryGridView** 真正瀑布流 |
| 卡片只显示标题 | **→** pin/done 图标 + 项目归属行 + 提醒行 |
| 长按弹出简陋菜单 | **→** 长按拖拽（reorder + 跨日期）+ 点击进入编辑面板 |
| 编辑仅 AlertDialog 改标题 | **→** 底部编辑面板：润色/项目/定时/复制 |
| 日历选中仅供展示 | **→** 日期筛选网格 + DragTarget 拖放 |
| AiService 仅非流式 | **→** +polishTodo +streamChat |

---

## 2. 数据模型变更

### TodoItem 新增字段

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `pinned` | `bool` | `false` | 置顶标记 |
| `sortOrder` | `int` | `0` | 手动排序（越大越靠前） |
| `reminderTime` | `String?` | `null` | 提醒时间 "HH:mm" 格式 |

`date` 字段（`String?`）即日起启用：`null` = 未分配日期（全局显示），非 null = 仅在该日显示。

### 排序规则

```
pinned 未完成（sortOrder 降序）
→ 未 pinned 未完成（sortOrder 降序）
→ pinned 已完成（sortOrder 降序）
→ 未 pinned 已完成（sortOrder 降序）
```

---

## 3. Keep 风格卡片布局

### 3.1 Masonry 瀑布流

- 包：`flutter_staggered_grid_view` 0.7.0
- `MasonryGridView.count(crossAxisCount: 2)`
- 每张卡片高度按内容估算（标题字数 + 是否显示项目行/提醒行）
- 不再区分用户/系统 todo 分区，合并显示

### 3.2 卡片交互分区

```
┌──────────────────────────────┐
│ [○/✓]  Title text     [📌]  │  ← 分区点击
│        项目名称 (若归属)      │
│        🕐 HH:mm (若有提醒)    │
└──────────────────────────────┘
```

| 区域 | 手势 | 行为 |
|------|------|------|
| 左上角图标 | 点击 | 切换 done |
| 右上角图标 | 点击 | 切换 pin |
| 卡片主体 | 点击 | 打开编辑面板 |
| 整张卡片 | 长按 | 拖拽模式 |

### 3.3 视觉状态

- **已完成**：整体 opacity 0.55，文字灰色 + 删除线
- **已 pin**：右上角 pin 图标实心高亮，边框 1.5px mintDeep
- **拖拽中**：原位半透明占位，反馈卡片带 elevation 阴影

---

## 4. 拖拽系统

### 4.1 架构

- 卡片外层：`LongPressDraggable<TodoItem>`（300ms 延迟）
- 网格单元格：`DragTarget<TodoItem>`（同日期 reorder）
- 日期 Chip：`DragTarget<TodoItem>`（跨日期分配）

### 4.2 行为

| 操作 | 结果 |
|------|------|
| 拖到另一卡片松手 | 交换 sortOrder（reorder） |
| 拖到今天/未来日期 Chip 松手 | 分配日期 → `updateTodoDate` |
| 拖到过去日期 Chip 松手 | 红色高亮 + toast「不能拖到过去的日期」 |
| 拖到网格空白区松手 | 回弹，无操作 |

---

## 5. 编辑面板

底部弹出面板（`showModalBottomSheet`），包含：

| 功能 | 图标 | 行为 |
|------|------|------|
| 文本编辑 | — | TextField，自动聚焦，支持多行 |
| 润色 | `auto_fix_high` | 调用 DeepSeek API → 预览润色结果 → 应用/重试 |
| 项目归属 | `folder` | 展开项目列表（无项目 + 已有项目），选中即更新 |
| 定时 | `timer` | TimePicker → 更新 reminderTime（长按清除） |
| 复制 | `copy` | Clipboard.setData + toast「已复制」 |
| 保存/删除 | — | 底部按钮行 |

---

## 6. AI 能力升级

| 方法 | 模型 | 类型 | 说明 |
|------|------|------|------|
| `polishTodo(text)` | deepseek-chat | 非流式 | 润色标题：凝练清晰、保留原意、2-20 字 |
| `streamChat(prompt)` | deepseek-chat | SSE 流式 | 预留能力，后续米糖 Tab 使用 |

---

## 7. 文件清单

### 修改（7 个）

| 文件 | 改动 |
|------|------|
| `lib/models/models.dart` | TodoItem +pinned +sortOrder +reminderTime |
| `lib/store/sumi_store_todos.dart` | 完全重写：新增 10+ mutation + sortedTodos/todosForSelectedDate |
| `lib/store/sumi_store.dart` | +aiService getter |
| `lib/services/ai_service.dart` | +polishTodo +streamChat |
| `lib/features/todos/todo_card.dart` | 完全重写：pin/done 分区点击 + 项目行 + 提醒行 |
| `lib/features/todos/todo_grid.dart` | 完全重写：MasonryGridView + DragTarget + 日期筛选 |
| `lib/features/todos/todos_page.dart` | +onTapBody → 编辑面板 |
| `lib/features/calendar/date_strip.dart` | _DateChip → DragTarget 包装 |
| `pubspec.yaml` | +flutter_staggered_grid_view |

### 新增（1 个）

| 文件 | 说明 |
|------|------|
| `lib/features/todos/todo_edit_sheet.dart` | 编辑面板：TextField + 四个操作按钮 + 润色预览 + 项目选择器 |

---

## 8. 验收清单

- [ ] Masonry 瀑布流：卡片两端对齐，不同高度自然排列
- [ ] 点击左上角 ○/✓ 切换完成态，完成后透明 + 沉底
- [ ] 点击右上角 📌 切换 pin 态，pin 后置顶 + 边框高亮
- [ ] 点击卡片正文 → 编辑面板弹出
- [ ] 编辑面板：TextField 编辑、润色调用 AI、项目归属切换、定时设置、复制
- [ ] 长按拖拽 → 拖到另一卡片 → reorder（sortOrder 交换）
- [ ] 长按拖拽 → 拖到未来日期 Chip → todo 分配日期
- [ ] 长按拖拽 → 拖到过去日期 Chip → 红色反馈 + toast
- [ ] 日历筛选：选中日期只显示该日 todo（含未分配日期的）
- [ ] 编译零 error

---

*文档版本：v1.0 · 2026-07-14*

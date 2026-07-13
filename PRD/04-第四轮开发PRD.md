# Sumi 04 轮开发 PRD — 米糖 Tab + 项目 AI 规划

## 概述

03 轮把 Todo 体验做到位了（Keep 瀑布流、pin/done、拖拽、编辑面板、SSE 能力储备）。04 轮有两个大目标：

- **A. 米糖 Tab**：新增第三个 Tab，提供 AI 对话助手界面，支持流式输出和多会话管理
- **B. 项目 AI 规划**：打通「项目 → AI 生成月计划 → 系统 todo」的完整链路

本轮**不做**工具调用（function calling），后续轮次再实现。

---

# Part A — 米糖 Tab（AI 对话助手）

## A1. 模型新增

### Conversation（会话）

```dart
class Conversation {
  final String id;           // conv-{timestamp}
  final String title;        // 会话标题（截取自首条用户消息，≤20 字）
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

### ChatMessage（消息）

```dart
class ChatMessage {
  final String id;           // msg-{timestamp}
  final String conversationId;
  final String role;         // 'user' | 'assistant'
  final String content;      // markdown 文本
  final DateTime createdAt;
}
```

copyWith / toJson / fromJson 完整实现。

---

## A2. 数据库变更

### 当前状态

`sumi_v1.db`，单表 `app_snapshot(id, body, updated_at)`，全量 JSON blob 持久化。

### 变更方案

数据库版本 1 → 2，`onUpgrade` 新增两张表：

```sql
CREATE TABLE conversations (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL,          -- 'user' | 'assistant'
  content TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_messages_conv ON messages(conversation_id, created_at);
```

### 新增 ChatPersist 服务

新建 `lib/data/chat_database.dart`：

```dart
class ChatDatabase {
  // CRUD 会话
  Future<List<Conversation>> loadConversations();
  Future<Conversation?> createConversation({String title});
  Future<void> deleteConversation(String id);
  Future<void> updateConversationTitle(String id, String title);

  // CRUD 消息
  Future<List<ChatMessage>> loadMessages(String conversationId);
  Future<void> saveMessage(ChatMessage message);
  Future<void> deleteMessages(String conversationId);
}
```

> **设计决策**：对话数据量大且读写频繁，不适合塞进全量 JSON snapshot。独立走 SQL 表查询，ChatDatabase 与 SumiSnapshotStore 共用同一个 Database 实例。

### 数据库实例共享

`SumiLocalDatabase` 暴露出 `Database` 实例供 `ChatDatabase` 复用，避免多连接竞争。

---

## A3. 导航变更

### main_shell.dart

当前 2 Tab → 3 Tab：

| Index | 标签 | 图标 | Widget |
|-------|------|------|--------|
| 0 | 事项 | `check_circle` | `TodosPage` |
| 1 | **米糖** | `psychology_rounded` / `forum_rounded` | **`ChatPage`** |
| 2 | 设置 | `settings` | `SettingsPage` |

新 Tab 插入中间位置，IndexedStack 保持懒加载。

---

## A4. UI 层

### 新增文件结构

```
lib/features/chat/
  chat_page.dart        # 主页面：会话列表 + 聊天区
  chat_bubble.dart      # 聊天气泡组件（用户 / AI）
  chat_input.dart       # 底部输入框 + 发送按钮
  conversation_list.dart # 侧滑抽屉 or 底部 Sheet：会话列表
```

### A4.1 ChatPage — 主页面

```
┌─────────────────────────────┐
│  ☰ 会话列表    Sumi（米糖）   │  ← AppBar
├─────────────────────────────┤
│                             │
│  ┌─────────────────────┐    │
│  │ 用户消息气泡          │    │
│  └─────────────────────┘    │
│        ┌─────────────────┐  │
│        │ AI 回复（流式）   │  │
│        └─────────────────┘  │
│                             │
├─────────────────────────────┤
│  [TextInput...............]  │  ← 底部输入栏
│  [发送]                      │
└─────────────────────────────┘
```

- 消息列表使用 `ListView.builder`，`reverse: true`（新消息在底部）
- 发送后自动滚到底部
- AppBar 左侧按钮打开会话列表抽屉

### A4.2 ChatBubble — 聊天气泡

- **用户气泡**：右对齐，mint 背景，圆角右下角为直角
- **AI 气泡**：左对齐，白色/浅灰背景，圆角左下角为直角
- AI 气泡支持 Markdown 渲染（使用 `flutter_markdown` 或简单文本样式处理 `**bold**` `- list` 等）
- AI 气泡流式输出时：光标闪烁效果，内容逐 chunk 追加

```
用户: ┌──────────────────┐
     │ 帮我看看今天的任务  │
     └──────────────────┘

AI:  ┌────────────────────────────┐
     │ 你今天有 3 个待办事项：      │
     │ 1. 复习数学第三章             │
     │ 2. ...                      │
     │ ▍（流式输出中）              │
     └────────────────────────────┘
```

### A4.3 ChatInput — 输入栏

- 圆角 TextField，支持多行（maxLines: 4）
- 发送按钮：mintDeep 圆形图标按钮
- 发送时禁用按钮 + loading 态
- 键盘弹起时消息列表随之上推（`reverse: true` 的 ListView 天然处理）

### A4.4 ConversationList — 会话列表

以底部 Sheet 或左侧 Drawer 展示：

```
┌─────────────────────────┐
│  对话历史        [+ 新建] │
├─────────────────────────┤
│  ● 帮我制定数学学习计划    │  ← 长按删除
│    3 条消息 · 2 小时前    │
├─────────────────────────┤
│  ● 今天学什么？          │
│    5 条消息 · 昨天       │
├─────────────────────────┤
│  ...                    │
└─────────────────────────┘
```

- 按 `updatedAt` 降序排列
- 点击切换会话
- 长按弹出删除确认
- 「+ 新建」按钮创建新会话

---

## A5. Store 变更

### 新增 sumi_store_chat.dart mixin

```dart
mixin SumiStoreChat on ChangeNotifier {
  // 状态
  List<Conversation> get conversations;
  String? get currentConversationId;
  List<ChatMessage> get currentMessages;
  bool get isStreaming;

  // 方法
  Future<void> loadConversations();
  Future<void> createConversation();
  Future<void> deleteConversation(String id);
  Future<void> switchConversation(String id);
  Future<void> sendMessage(String content);  // 流式输出
  Future<void> regenerateLast();            // 重试最后一条
}
```

### 流式发送流程

```
sendMessage(content)
  → saveMessage(userMsg) 到 DB
  → 构建 messages 上下文（最近 N 轮 + system prompt）
  → AiService.streamChat(fullPrompt)  // 复用 03 轮的 SSE 方法
  → 逐 chunk 追加到临时 assistant 消息
  → 流结束后 saveMessage(assistantMsg) 到 DB
  → afterMutation()
```

### System Prompt（米糖对话）

```
你是 Sumi（米糖），一个温暖的个人学习助手。
你的风格：鼓励、简洁、有同理心。像朋友一样聊天，不要像机器人。

你可以帮用户：
- 制定和调整学习计划
- 解答学习中的疑问
- 管理待办事项
- 提供学习建议和鼓励

回答控制在 200 字以内，除非用户明确需要详细解释。
```

### 上下文窗口

- 每次发送携带最近 **10 轮**对话（20 条消息）作为上下文
- System prompt 始终作为第一条消息

---

## A6. AiService 适配

`streamChat` 方法（03 轮已实现）需要增强：

```dart
// 新增：带消息历史的流式对话
Stream<String> streamChatWithHistory({
  required String systemPrompt,
  required List<Map<String, String>> history,  // [{role, content}, ...]
  required String userMessage,
});
```

或直接在现有 `streamChat` 上扩展参数，传入完整 messages 数组。

---

# Part B — 项目 AI 规划 → 系统 Todo

## B1. 核心链路

```
用户创建/编辑项目
  → 触发 AI 规划（goal + level + cycleMonths + timeConstraint）
  → AI 一次性生成全部月卡（按月分解，内容根据当月实际剩余天数缩放）
  → AI 生成当月第一天的系统 todo
  → 全部月卡存入（但只披露当月）
  → 后续天数/月份：App 启动时自动检测并生成
```

### 关键原则

| 原则 | 说明 |
|------|------|
| **全量生成，只披露当月** | 用户设 6 个月周期 → AI 生成 6 张月卡全部保存，但 UI 只显示 currentMonthIndex 对应的那张 |
| **按真实月份生成** | 月卡绑定真实月份（如"2026 年 7 月"），内容量根据当月剩余天数缩放（剩 6 天 → 计划紧凑，剩 30 天 → 计划充裕） |
| **每日 todo 数量** | 默认 1 条/天，后续根据用户建模调整（max 30, min 1） |
| **月末结算** | 当月结束时 AI 分析完成情况 → 调整下月月卡内容 → 再生成下月每日 todo |
| **懒触发** | 新的一天/新月 → App 启动时检测 → 自动生成当天 todo / 披露新月卡 |

### 完整时序

```
Day 1 (项目创建日):
  AI 生成全部 6 张月卡（存入，只披露月 0）
  AI 生成 Day 1 的系统 todo（存入，显示）

Day 2 启动:
  检测：新的一天 → AI 生成 Day 2 的系统 todo

...

月末最后一天后，次月 1 日启动:
  检测：新月 → 披露月 1 月卡 → AI 生成 Day 1 的系统 todo
  （月末结算逻辑本轮做结构预留，完整实现在后续轮次）
```

---

## B2. 模型变更

### MonthCard 扩展

现有 MonthCard 已足够（`title` + `summary`），但需增加一个字段标记内容来源：

```dart
class MonthCard {
  // ... 现有字段保持不变 ...
  final bool aiGenerated;  // 是否 AI 生成（true = AI 填充，false = 用户手动编辑）
}
```

- AI 生成时 `aiGenerated = true`
- 用户手动编辑月卡时 `aiGenerated = false`
- 月末 AI 重新规划时覆盖 `aiGenerated = true`

### 新增 PlanResult（AI 规划解析结果，非持久化模型）

```dart
/// AI 返回的规划 JSON 解析结果（中间态，不持久化）。
class PlanResult {
  final List<MonthPlanItem> monthPlans;
  final List<TodoSeed> todayTodos;
}

class MonthPlanItem {
  final int monthIndex;    // 0, 1, 2, ...
  final String title;      // 月主题
  final String summary;    // 月计划摘要
}

class TodoSeed {
  final String title;
  final String? body;
  final String date;       // "YYYY-MM-DD"
}
```

---

## B3. AI 规划 Prompt 设计

### System Prompt（项目规划）

```
你是 Sumi（米糖），一个专业的自学规划师。

用户正在创建一个自学项目，你需要根据项目信息为其生成完整的学习计划。

## 输入信息
- 项目目标：{goal}
- 当前水平：{level}
- 规划周期：{cycleMonths} 个月
- 每周投入时间：{timeConstraint} 小时
- 起始日期：{startDate}

## 要求

### 月计划
- 为每个月生成一个月计划卡
- 每月有一个凝练的主题（5-15 字）和详细摘要（30-100 字）
- 摘要要高维度、战略性，不要过于具体（具体步骤留给每日 todo）
- 内容量匹配当月实际天数：如果起始月份剩余天数少（如只剩 6 天），计划应紧凑
- 各月之间应有递进关系（基础 → 进阶 → 综合）

### 每日 Todo（仅生成第一天的）
- 基于第一个月计划拆解为具体的可执行 todo
- 标题 2-20 字，可附带更详细的 body
- 数量：1 条（默认）
- 考虑每周投入时间约束，不要超出用户能力

## 输出格式
严格按以下 JSON 格式输出，不要带任何额外文字：

{
  "monthPlans": [
    {
      "monthIndex": 0,
      "title": "月主题",
      "summary": "月计划摘要..."
    },
    ...
  ],
  "todayTodos": [
    {
      "title": "todo 标题",
      "body": "更详细的说明（可选）",
      "date": "YYYY-MM-DD"
    }
  ]
}
```

### 每日 Todo 生成 Prompt（后续天数）

```
你是 Sumi（米糖）。根据当前月计划，为指定日期生成 1 条系统 todo。

月计划：{monthPlanTitle} — {monthPlanSummary}
日期：{date}
本周已安排的小时数：{scheduledHours} / {timeConstraint}

要求：todo 标题 2-20 字，可附带 body。输出 JSON：
{"todos": [{"title": "...", "body": "...", "date": "YYYY-MM-DD"}]}
```

---

## B4. AiService 新增方法

```dart
/// 项目规划：根据项目信息生成全部月计划 + 当天 todo。
/// 返回 null = 失败，调用方应降级（创建空月卡，无系统 todo）。
Future<PlanResult?> generateProjectPlan({
  required String goal,
  required String level,
  required int cycleMonths,
  required int timeConstraint,
  required DateTime startDate,
});

/// 生成指定日期的系统 todo（基于给定月卡）。
/// 返回 null = 失败。
Future<List<TodoSeed>?> generateDailyTodos({
  required String monthPlanTitle,
  required String monthPlanSummary,
  required String date,
  required int timeConstraint,
  required int scheduledHours,
});
```

- 使用 `deepseek-chat` 模型，`response_format: {type: 'json_object'}`
- 超时 60s（规划 prompt 较长，token 消耗大）
- JSON 解析失败 → 返回 null，调用方降级

---

## B5. Store 变更

### sumi_store_projects.dart 改造

**`addProject` 流程改造：**

```
addProject(...)
  → 创建 Project 对象（currentMonthIndex = 0）
  → 创建 cycleMonths 张空白月卡（月卡绑定真实月份）
  → afterMutation()
  → 异步触发 _triggerPlanning(projectId)
```

**新增 `_triggerPlanning`：**

```
_triggerPlanning(projectId)
  → 调用 AiService.generateProjectPlan(...)
  → 成功：
    - 更新全部月卡（title, summary, aiGenerated = true）
    - 创建当天系统 todo
    - afterMutation()
  → 失败：
    - 月卡保持空白，用户可手动填充
    - toast「AI 规划生成失败，请检查网络后重试」
```

**新增 `checkAndGenerateDaily`（App 启动时调用）：**

```
checkAndGenerateDaily()
  → 遍历每个活跃项目：
    - 检查今天是否已有系统 todo → 跳过
    - 没有 → 调用 AiService.generateDailyTodos(...) → 创建系统 todo
    - 如果是新月（date.month != lastGeneratedMonth）：
      - advanceCurrentMonth()（披露新月卡）
      - 生成第一天 todo
  → afterMutation()
```

**新增 `retryPlanning`（手动重试）：**

```
retryPlanning(projectId)
  → 重新调用 AI 规划
  → 覆盖现有月卡和当天系统 todo
```

### sumi_store.dart 启动流程增强

`SumiStore.create()` 工厂方法中，加载数据后：

```dart
// 数据加载完毕
store.checkAndGenerateDaily();
```

### 月卡绑定真实月份

现有 `MonthCard.monthIndex` 是相对索引（0, 1, 2...）。UI 显示时根据项目起始日期 + monthIndex 计算真实月份：

```dart
// month_card_pager.dart 中已有类似逻辑
final cardDate = DateTime(now.year, now.month + monthIndex, 1);
final monthLabel = '${cardDate.year}年${cardDate.month}月';
```

此处需考虑跨年：`DateTime(year, month + monthIndex, 1)` 会自动处理。

---

## B6. UI 变更

### B6.1 ProjectEditor 增强

创建项目对话框中，`timeConstraint` 和 `cycleMonths` 从当前的下拉选择改为**可滚动的数字选择器**（参考 classugar 的滚轮逻辑）：

```
┌─────────────────────────────┐
│  创建项目                     │
│                              │
│  名称：[_______________]     │
│  颜色：● ● ● ● ●            │
│  目标：[_______________]     │
│  水平：[_______________]     │
│                              │
│  周期：[ 6 个月 ]  ← 可滚动   │
│  每周投入：[ 10 小时 ] ← 可滚动│
│                              │
│  [取消]           [创建]     │
└─────────────────────────────┘
```

- `cycleMonths`：1-12 月，使用 `ListWheelScrollView` 或数字 +/- 按钮
- `timeConstraint`：0-40 小时/周，步长 1

### B6.2 月卡 UI 增强

当月卡为 AI 生成时，显示 AI 标记：

```dart
// _UnlockedCard 中
if (card.aiGenerated)
  Row([
    Icon(Icons.auto_awesome_rounded, size: 12, color: mintDeep),
    Text('AI 规划', style: ...),
  ])
```

### B6.3 项目卡片的"重新规划"按钮

在 ProjectCard 或月卡区域增加"重新规划"按钮，触发 `retryPlanning`。

---

## B7. 月末结算逻辑（架构预留）

本轮**不完整实现**月末结算，但做好架构准备：

### 预留接口

```dart
/// 月末结算 —— 分析当月完成情况，调整下月计划。
/// 本轮实现桩（stub），后续轮次接入用户建模数据。
Future<void> settleMonth(String projectId) async {
  final project = /* 查找项目 */;
  final thisMonthCards = /* 当月月卡 */;
  final completedTodos = /* 当月已完成的系统 todo */;
  final totalTodos = /* 当月全部系统 todo */;

  // 调用 AI 分析并调整下月计划
  // （本轮不做，后续轮次实现）
}
```

### 触发时机预留

```dart
// checkAndGenerateDaily 中
if (isNewMonth) {
  await settleMonth(projectId);  // 桩：本轮跳过
  advanceCurrentMonth();
  // 生成新月第一天 todo
}
```

---

## 8. 文件清单

### 新增文件（7 个）

| 文件 | 说明 |
|------|------|
| `lib/features/chat/chat_page.dart` | 米糖 Tab 主页面 |
| `lib/features/chat/chat_bubble.dart` | 聊天气泡组件（用户/AI 双态） |
| `lib/features/chat/chat_input.dart` | 底部输入栏 |
| `lib/features/chat/conversation_list.dart` | 会话列表 Sheet/Drawer |
| `lib/data/chat_database.dart` | 对话数据 SQL 操作层 |
| `lib/store/sumi_store_chat.dart` | 对话状态管理 mixin |
| `lib/services/planning_service.dart` | 项目规划 prompt 构建 + JSON 解析（从 AiService 拆分） |

### 修改文件（11 个）

| 文件 | 改动 |
|------|------|
| `lib/models/models.dart` | +Conversation, +ChatMessage；MonthCard +aiGenerated |
| `lib/main_shell.dart` | 2 Tab → 3 Tab，插入米糖 Tab |
| `lib/services/ai_service.dart` | +generateProjectPlan(), +generateDailyTodos()；streamChat 增强支持消息历史 |
| `lib/store/sumi_store.dart` | +SumiStoreChat mixin；启动时调用 checkAndGenerateDaily |
| `lib/store/sumi_store_projects.dart` | addProject 流程改造；+checkAndGenerateDaily, +retryPlanning, +_triggerPlanning |
| `lib/store/sumi_store_persist.dart` | snapshot 序列化增加 conversations 引用（或独立存储） |
| `lib/data/local_database.dart` | DB version 1→2；onUpgrade 新增 conversations/messages 表；暴露 Database 实例 |
| `lib/features/projects/project_editor.dart` | cycleMonths / timeConstraint 改为滚轮选择器 |
| `lib/features/projects/project_card.dart` | +重新规划按钮 |
| `lib/features/calendar/month_view_sheet.dart` | AI 生成月卡的标记显示 |
| `lib/features/projects/month_card_pager.dart` | AI 生成标记 + 内容展示优化 |

### 不修改的文件（无变更）

| 文件 | 原因 |
|------|------|
| `lib/features/todos/*` | 本轮不涉及 todo 卡片/网格/编辑面板 |
| `lib/features/calendar/date_strip.dart` | 无变更 |
| `pubspec.yaml` | 本轮无新依赖（`flutter_markdown` 如需要再加，先手写简单 markdown 解析） |

---

## 9. 实施顺序

```
Phase 1: 数据层
  1. models.dart — Conversation + ChatMessage + MonthCard.aiGenerated
  2. local_database.dart — DB migration v1→v2, 新增 conversations/messages 表
  3. chat_database.dart — 对话 SQL CRUD

Phase 2: AI 规划
  4. ai_service.dart — +generateProjectPlan(), +generateDailyTodos(); streamChat 增强
  5. sumi_store_projects.dart — addProject 改造 + _triggerPlanning + checkAndGenerateDaily

Phase 3: 米糖 Tab UI
  6. chat_bubble.dart — 聊天气泡组件
  7. chat_input.dart — 输入栏
  8. conversation_list.dart — 会话列表
  9. chat_page.dart — 主页面组装
  10. sumi_store_chat.dart — 对话状态 mixin
  11. sumi_store.dart — 集成 SumiStoreChat + 启动检测

Phase 4: 导航 + 项目 UI
  12. main_shell.dart — 3 Tab
  13. project_editor.dart — 滚轮选择器
  14. project_card.dart — +重新规划
  15. month_view_sheet.dart / month_card_pager.dart — AI 标记

Phase 5: 收尾
  16. sumi_store_persist.dart — 序列化更新
  17. flutter analyze 验证零错误
```

---

## 10. 风险与降级

| 风险 | 降级方案 |
|------|----------|
| DB migration 失败（用户已有数据） | migration 中 try-catch；失败则重建 conversations/messages 表，不影响 app_snapshot 数据 |
| AI 规划 JSON 解析失败 | 返回 null，月卡保持空白，用户手动填充；toast 提示重试 |
| 规划 token 消耗过大（6 月全量生成） | 限制 max_tokens 2000；超长计划截断 |
| streamChat 携带历史后首 token 延迟大 | 首轮仅携带 system prompt + 当前消息，后续轮次逐步增加上下文 |
| 聊天数据写入 performance | 单条 insert，不在 UI 线程 await；批量写入使用 transaction |
| 月末跨年 monthIndex 计算错误 | 统一使用 `DateTime(year, month + monthIndex, 1)` 自动处理 |

---

## 11. 验证清单

### Part A
- [ ] 第三个 Tab「米糖」正常显示和切换
- [ ] 新建会话 → 自动生成标题
- [ ] 发送消息 → AI 流式回复（逐 chunk 渲染）
- [ ] 切换历史会话 → 加载历史消息
- [ ] 删除会话 → 级联删除消息
- [ ] 会话列表按最近更新时间排序
- [ ] 断网发送 → 用户消息仍保存，AI 回复显示失败提示
- [ ] DB migration 在已有数据上升级不丢数据

### Part B
- [ ] 创建项目（含 goal/level/cycle/timeConstraint）→ AI 生成全部月卡 + 当天系统 todo
- [ ] 月卡按真实月份显示（如"2026 年 7 月"），内容量随剩余天数变化
- [ ] 只披露当月月卡，未来月卡锁定
- [ ] 跨天后启动 App → 自动生成当天系统 todo
- [ ] 跨月后启动 App → 披露新月卡 + 生成当天系统 todo
- [ ] AI 规划失败 → 月卡空白，手动重试可恢复
- [ ] cycleMonths / timeConstraint 滚轮选择正常工作
- [ ] 月卡上显示 AI 生成标记
- [ ] flutter analyze 零错误

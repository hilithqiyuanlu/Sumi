# 05 轮开发 PRD — Sumi Agent 能力

## 概述

为 Sumi 实现轻量 Agent 能力：工具调用（Tool Calling）、Agent Loop、MEMORY.md 持久记忆、模型迁移至 DeepSeek V4 系列 + thinking 模式、对话风格打磨。

---

## 1. 模型迁移

### 1.1 双模型策略

本轮同时引入两个 DeepSeek V4 模型，按场景分配：

| 模型 | 价格（输入/输出，每百万 token） | 适用场景 |
|------|--------------------------------|----------|
| `deepseek-v4-flash` | $0.14 / $0.28 | 日常对话、工具调用、拆分/润色/每日 todo |
| `deepseek-v4-pro` | $1.74 / $3.48 | 项目月规划（重推理任务） |

> **背景**：DeepSeek 将于 2026-07-24 停用 `deepseek-chat` / `deepseek-reasoner`，必须迁移至 V4 系列。

### 1.2 各场景模型与 Thinking 分配

| # | 场景 | 模型 | Thinking | 理由 |
|---|------|------|----------|------|
| 1 | `splitTodo` | flash | ❌ | 简单判断，不需推理 |
| 2 | `polishTodo` | flash | ❌ | 简单润色，不需推理 |
| 3 | `generateProjectPlan` | **pro** | ✅ `thinking` | 最重的推理任务，pro 质量 + thinking |
| 4 | `generateDailyTodos` | flash | ❌ | 基于已有月卡的简单生成 |
| 5 | `streamChatMessages` | flash | ✅ `thinking` | 始终开启 — flash 够便宜，确保工具调用决策质量一致 |

### 1.3 Thinking 参数

在请求体顶层传入（与 `model`、`messages` 平级）：

```json
{
  "thinking_mode": "thinking"
}
```

使用 `thinking`（中等推理），不做 `thinking_max`。

> **注意**：`thinking_mode` 不是 `extra_body`，是请求 body 的顶层字段。

### 1.4 reasoning_content 处理

开启 thinking 后，API 返回的 assistant 消息会额外包含 `reasoning_content` 字段（模型的思考过程文本）。

**规则**：
- 流式解析时，从 `delta.reasoning_content` 提取思考过程
- 保存到 `ChatMessage.reasoningContent` 字段
- 后续请求构建消息历史时，**必须将 assistant 消息的 `reasoning_content` 原样传回**
- 如果某条 assistant 消息没有 `reasoning_content`，不要补空字符串

### 1.5 其他参数调整

- `temperature`: 1.0（DeepSeek V4 推荐默认值）
- `top_p`: 1.0

---

## 2. Tool Calling 系统

### 2.1 工具定义

本轮实现 5 个工具：

| 工具名 | 说明 | 参数 |
|--------|------|------|
| `search_web` | Tavily 网络搜索 | `query` (string, required) |
| `read_memory` | 读取 MEMORY.md | 无参数 |
| `write_memory` | 写入/追加 MEMORY.md | `content` (string, required) — 要写入的完整记忆内容 |
| `read_todos` | 查询当前 todo 列表 | `filter` (string, optional) — 筛选条件，如 "today" / "project:xxx" / "all" |
| `write_todo` | 创建新 todo | `title` (string, required), `date` (string, optional), `projectId` (string, optional), `body` (string, optional) |

每个工具按 OpenAI function calling 格式定义：

```json
{
  "type": "function",
  "function": {
    "name": "search_web",
    "description": "搜索网络获取实时信息...",
    "parameters": {
      "type": "object",
      "properties": { ... },
      "required": [...]
    }
  }
}
```

### 2.2 流式解析 tool_calls

当前 `streamChatMessages` 只解析 `delta.content`。需增加对 `delta.tool_calls` 的解析：

```
delta.tool_calls[0].index          // tool call 序号
delta.tool_calls[0].id              // tool call ID（首个 chunk 携带）
delta.tool_calls[0].function.name   // 函数名（首个 chunk 携带）
delta.tool_calls[0].function.arguments  // 增量 JSON 片段
```

**解析策略**：为每个 tool call 维护一个 buffer，逐 chunk 拼接 arguments，直到所有 tool_calls 的 arguments 可以解析为完整 JSON。

**StreamEvent 类型**：

```dart
sealed class StreamEvent {}
class ContentDelta extends StreamEvent { final String text; }
class ReasoningDelta extends StreamEvent { final String text; }
class ToolCallsComplete extends StreamEvent { final List<ToolCall> calls; }
class StreamDone extends StreamEvent {}
```

`streamChatMessages` 返回类型从 `Stream<String>` 改为 `Stream<StreamEvent>`。

### 2.3 工具执行器

```dart
class ToolExecutor {
  Future<String> execute(ToolCall call);
}
```

每个工具的执行是同步/异步函数，返回字符串结果（tool result message）。

- `search_web` → Tavily API
- `read_memory` → 读取本地 MEMORY.md 文件
- `write_memory` → 写入本地 MEMORY.md 文件
- `read_todos` → 查询 SumiStore.todoItems
- `write_todo` → 调用 SumiStore.addSystemTodo

---

## 3. Agent Loop

### 3.1 流程

```
用户发送消息
  ↓
构建 messages（含 system prompt + 历史 + reasoning_content）
  ↓
┌─ Agent Loop（最多 5 轮）─┐
│                            │
│  API 流式调用              │
│    ↓                       │
│  解析 StreamEvent          │
│    ├─ ContentDelta → UI    │
│    ├─ ReasoningDelta → UI  │
│    └─ ToolCallsComplete    │
│         ↓                  │
│  执行工具                   │
│    ↓                       │
│  工具结果追加到 messages    │
│    ↓                       │
│  如果是最终回复 → 退出循环  │
│  如果有 tool_calls → 继续   │
│                            │
└────────────────────────────┘
  ↓
保存完整对话到 DB
  ↓
通知 UI 刷新
```

### 3.2 终止条件

1. API 返回仅 content，无 tool_calls → 正常结束
2. 达到最大轮数（5）→ 强制要求模型总结
3. 用户中断 → 保留已生成内容

### 3.3 中断处理

用户可在 agent loop 执行期间通过再生按钮或发送新消息中断当前 loop。

---

## 4. MEMORY.md

### 4.1 存储位置

```
<app_documents>/sumi/MEMORY.md
```

首次运行时自动创建空文件。

### 4.2 格式

与 Claude Code MEMORY.md 格式保持一致：

```markdown
## 用户偏好
- 喜欢简洁直接的回复
- 每晚 8-10 点学习

## 学习记录
- 2026-07-10 完成了线性代数第一章
```

### 4.3 工具行为

- `read_memory`：读取完整 MEMORY.md 作为文本传入消息
- `write_memory`：将 content 参数追加到 `### 记忆 {timestamp}` 标题下，不覆盖已有内容

---

## 5. ChatMessage 模型更新

### 5.1 新增字段

```dart
class ChatMessage {
  // ... 现有字段
  final String? reasoningContent;   // AI 思考过程（仅 assistant 消息）
  final String? toolCallsJson;      // 工具调用 JSON（仅 assistant 消息，用于 DB 持久化）
}
```

### 5.2 copyWith / toJson / fromJson 同步更新

`copyWith` 增加 `reasoningContent`、`toolCallsJson` 参数。

---

## 6. Database 迁移 v2 → v3

### 6.1 messages 表新增列

```sql
ALTER TABLE messages ADD COLUMN reasoning_content TEXT;
ALTER TABLE messages ADD COLUMN tool_calls_json TEXT;
```

### 6.2 迁移实现

`local_database.dart` 的 `onUpgrade` 回调中处理 `oldVersion < 3`，为已有 messages 表增加上述两列。

### 6.3 chat_database.dart 更新

- `saveMessage`：写入 `reasoning_content` 和 `tool_calls_json`
- `loadMessages`：读取 `reasoning_content` 和 `tool_calls_json`
- `updateMessageContent`：更新 content（流式结束后），同步更新 reasoning_content 和 tool_calls_json

---

## 7. AI 服务改造

### 7.0 模型常量

```dart
static const _modelFlash = 'deepseek-v4-flash';
static const _modelPro = 'deepseek-v4-pro';
```

各方法按 1.2 表格选择模型和 thinking 开关。实现上建议用内部辅助方法统一构建请求体参数：

```dart
Map<String, Object?> _buildRequestParams({
  required String model,
  required List<Map<String, Object?>> messages,
  bool thinking = false,
  bool stream = false,
  List<Map<String, Object?>>? tools,
  int maxTokens = 1000,
});
```

### 7.1 新增 Tavily 搜索

```dart
Future<List<Map<String, String>>?> searchWeb(String query);
```

- 调用 Tavily Search API
- 返回 `[{title, url, snippet}]`
- API key 与 DeepSeek key 一起在设置页配置

### 7.2 streamChatMessages 重写

- 模型：`deepseek-v4-flash`，始终开启 `thinking_mode: "thinking"`
- 返回类型从 `Stream<String>` 改为 `Stream<StreamEvent>`
- 在请求体中携带 `tools` 定义
- 解析 delta 时区分 `content` / `reasoning_content` / `tool_calls`
- 消息构建时附带 assistant 消息的 `reasoning_content` 和 `tool_calls`

### 7.3 新增 sendAgentLoop 方法

```dart
Stream<StreamEvent> sendAgentLoop({
  required List<Map<String, Object?>> messages,
  required List<Map<String, Object?>> tools,
  int maxTurns = 5,
});
```

封装 agent loop 逻辑，内部多轮调用 `streamChatMessages`，自动执行工具。

### 7.4 非流式方法更新

- `splitTodo`：`deepseek-v4-flash`，关闭 thinking
- `polishTodo`：`deepseek-v4-flash`，关闭 thinking
- `generateProjectPlan`：`deepseek-v4-pro`，开启 `thinking_mode: "thinking"`（唯一使用 pro 的场景）
- `generateDailyTodos`：`deepseek-v4-flash`，关闭 thinking
- `chat`（预留非流式）：`deepseek-v4-flash`，关闭 thinking

---

## 8. Store 变更

### 8.1 sumi_store_chat.dart — sendMessage 重写

`sendMessage` 方法改为使用 agent loop：

```dart
Future<void> sendMessage(String content) async {
  // 1. 保存用户消息
  // 2. 构建 messages（含 reasoning_content）
  // 3. 调用 aiService.sendAgentLoop()
  // 4. 解析 StreamEvent：
  //    - ContentDelta → 更新 UI 文本
  //    - ReasoningDelta → 保存到 chatMessage.reasoningContent（UI 可选展示）
  //    - ToolCallsComplete → 在 UI 消息列表中插入工具调用提示
  // 5. loop 结束后持久化完整消息到 DB
}
```

### 8.2 新增状态字段

```dart
bool _isThinking = false;         // 是否正在思考（reasoning）
String? _currentToolCallLabel;    // 当前执行的工具名称（用于 UI 状态提示）
```

### 8.3 MEMORY.md 管理

```dart
Future<String> readMemory();
Future<void> appendMemory(String content);
```

使用 `path_provider` 获取 app 文档目录。

### 8.4 AI 设置扩展

设置页 AI 配置区域新增：
- Tavily API Key 输入框
- 现有 DeepSeek API Key 保持不变

---

## 9. System Prompt 重新设计

### 9.1 新 prompt

```
你是 Sumi，一个能干的个人学习助手。你有工具可以帮助用户。

## 风格
- 简洁直接，像朋友聊天，不要机器人套话
- 用户没要求时，默认 ≤ 100 字
- 不要用"当然可以！""希望对你有帮助！"这类 AI 废话
- 用思考和工具来做对的事，而不是问用户每一步怎么走

## 工具
你可以搜索网络、读写记忆、管理待办事项。需要时直接用工具，不要问用户"要不要我帮你搜"。

## 记忆
使用 read_memory / write_memory 记录用户的重要信息、偏好和学习进度。
```

### 9.2 关键变化

- 字数限制从 200 → 100 字默认
- 主动使用工具，少问用户
- 去除 "温暖的""鼓励" 等矫饰词
- 增加工具使用引导

---

## 10. UI 变更

### 10.1 chat_bubble.dart — 工具调用气泡

新增 `ToolCallBubble` widget：

```
┌──────────────────────────────────┐
│ 🔧 搜索网络中...                 │  ← 执行中：灰色 + 加载动画
│ 🔧 已搜索 · 3 条结果             │  ← 完成：浅浅 mint 底色
│ 🔧 已创建事项                    │
│ 🔧 已更新记忆                    │
└──────────────────────────────────┘
```

紧凑、小字号、圆角标签风格。

### 10.2 chat_bubble.dart — 思考过程（可选收起）

AI 气泡上方可选显示 "思考中..." 的可展开区域（类似 ChatGPT 的思考过程折叠）：

```
┌──────────────────────────────────┐
│ ▶ 思考过程                       │  ← 折叠态
│ ▼ 思考过程                       │  ← 展开态
│   用户说想学线代，已经有基础...    │
│   我应该先查一下记忆看之前...     │
└──────────────────────────────────┘
```

默认折叠。仅当消息有 `reasoningContent` 时显示。

### 10.3 chat_page.dart — 状态展示

- AppBar 标题旁：正在执行工具时显示 "🔧 xxx中..."
- 流式输出中保持现有滚动行为

### 10.4 settings_page.dart — AI 配置扩展

AI 设置区域增加：
- `Tavily API Key` 输入框（带隐藏/显示切换，参考现有 key 输入）

### 10.5 设置数据持久化

- Tavily API Key 使用现有的 key-value 存储方式（与 DeepSeek key 一致）

---

## 11. 新增依赖

```yaml
path_provider: ^2.1.0   # 获取 app 文档目录（MEMORY.md 存储）
```

---

## 12. 文件清单

### 修改文件（11 个）

| 文件 | 改动 |
|------|------|
| `lib/models/models.dart` | ChatMessage +reasoningContent +toolCallsJson, 更新 copyWith/toJson/fromJson |
| `lib/data/local_database.dart` | DB v2→v3 迁移：messages 表 +reasoning_content +tool_calls_json |
| `lib/data/chat_database.dart` | saveMessage/loadMessages/updateMessageContent 支持新字段 |
| `lib/services/ai_service.dart` | 双模型常量 + `_buildRequestParams`；streamChatMessages → Stream<StreamEvent>；+sendAgentLoop；+searchWeb；各方法按场景分配模型和 thinking |
| `lib/store/sumi_store_chat.dart` | sendMessage 重写为 agent loop；+_isThinking +_currentToolCallLabel；+readMemory +appendMemory；新 system prompt |
| `lib/store/sumi_store.dart` | +tavilyApiKey 配置存储；集成 MEMORY.md 管理 |
| `lib/store/sumi_store_persist.dart` | Tavily key 持久化 |
| `lib/features/chat/chat_bubble.dart` | +ToolCallBubble +思考过程折叠区域；StreamEvent → UI 适配 |
| `lib/features/chat/chat_page.dart` | AppBar 工具状态提示；适配 StreamEvent |
| `lib/features/chat/chat_input.dart` | 工具执行期间禁用输入（与 isStreaming 共用 enabled 逻辑） |
| `pubspec.yaml` | +path_provider |

### 新增文件（2 个）

| 文件 | 说明 |
|------|------|
| `lib/services/tool_executor.dart` | 工具执行器：5 个工具的实现 |
| `lib/services/tavily_service.dart` | Tavily Search API 封装 |

---

## 13. 实施顺序

```
Phase 1: 数据层
  1. ChatMessage 模型 +reasoningContent +toolCallsJson
  2. local_database.dart v2→v3 migration
  3. chat_database.dart 新字段读写

Phase 2: API 层
  4. StreamEvent 类型定义
  5. ai_service.dart — 模型切换 + thinking_mode + 工具定义
  6. ai_service.dart — streamChatMessages 重写（Stream<StreamEvent> + tool_calls 解析）
  7. ai_service.dart — sendAgentLoop（agent loop 封装）
  8. tavily_service.dart + tool_executor.dart

Phase 3: Store 层
  9. sumi_store_chat.dart — sendMessage 重写为 agent loop
 10. sumi_store.dart + persist — Tavily key + MEMORY.md 管理
 11. System prompt 重新设计

Phase 4: UI 层
 12. chat_bubble.dart — ToolCallBubble + 思考过程折叠
 13. chat_page.dart — 工具状态提示 + StreamEvent 适配
 14. settings_page.dart — Tavily API Key 配置
 15. pubspec.yaml + flutter pub get

Phase 5: 收尾
 16. flutter analyze 验证
```

---

## 14. 风险与降级

| 风险 | 降级方案 |
|------|----------|
| `reasoning_content` 传回逻辑与 DeepSeek 实际行为不一致 | 查阅最新文档，加入 defensive check：传回前校验字段存在 |
| Agent loop 轮数过多导致响应慢 | loop 内每轮都 yield StreamEvent 给 UI，用户可随时中断；上限 5 轮 |
| Tavily API 不可用或限额 | 静默降级：工具返回错误文本，AI 可告知用户搜索暂时不可用 |
| Streaming + tool_calls 解析复杂 | tool_calls 的 arguments 片段拼接完后再解析 JSON；解析失败视为无工具调用 |
| `deepseek-v4-flash` API 行为与当前 `deepseek-chat` 不一致 | 先在一个单独的测试方法中验证参数格式，确认后再迁移 |
| MEMORY.md 文件过大导致上下文超限 | read_memory 返回时限制长度（取最近 2000 字），提示 AI 精简写入 |

---

## 15. 验证

- [ ] `generateProjectPlan` 使用 deepseek-v4-pro + thinking，返回质量达标
- [ ] `streamChatMessages` 使用 deepseek-v4-flash + thinking，tool calling 决策正确
- [ ] thinking_mode 按场景正确开/关（非流式方法关，chat 和 pro 规划开）
- [ ] reasoning_content 在 multi-turn agent loop 中正确传回
- [ ] 5 个工具均可被 AI 正确调用
- [ ] Agent loop 正确执行多轮（如：搜索 → 分析 → 创建 todo）
- [ ] Agent loop 达到最大轮数时正常终止
- [ ] 用户中断 agent loop 后状态正确恢复
- [ ] MEMORY.md 可正确读写
- [ ] 对话历史跨会话恢复后 reasoning_content 不丢失
- [ ] 工具调用气泡正确展示（执行中/完成态）
- [ ] 思考过程可展开/折叠
- [ ] 新 system prompt 风格更简洁、主动使用工具
- [ ] DB 升级 v2→v3 平滑（已有数据不丢失，新字段有默认值）
- [ ] Tavily key 正确存储和读取
- [ ] flutter analyze 零错误

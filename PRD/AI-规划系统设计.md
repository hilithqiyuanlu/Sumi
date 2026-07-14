# Sumi AI 与规划系统设计文档

> 最后更新：2026-07-14  
> 涵盖：AI 模型策略、Tool Calling、Agent Loop、项目规划全流程、每日 Todo 生成、MEMORY.md 记忆系统

---

## 目录

1. [AI 模型与能力矩阵](#1-ai-模型与能力矩阵)
2. [项目规划系统](#2-项目规划系统)
3. [每日 Todo 自动生成](#3-每日-todo-自动生成)
4. [Agent Loop 对话系统](#4-agent-loop-对话系统)
5. [工具系统](#5-工具系统)
6. [MEMORY.md 记忆系统](#6-memorymd-记忆系统)
7. [数据模型](#7-数据模型)
8. [完整流程图](#8-完整流程图)

---

## 1. AI 模型与能力矩阵

### 1.1 双模型策略

| 模型 | API 名称 | 用途 | Thinking | 原因 |
|------|----------|------|----------|------|
| **Flash** | `deepseek-v4-flash` | 日常对话、todo 拆分/润色、每日 todo 生成 | 对话可开关，其余关 | 速度快、成本低，适合高频轻量任务 |
| **Pro** | `deepseek-v4-pro` | 项目规划 | ✅ 开启 | 规划需要深度推理，值得用更强的模型 |

> 代码位置：[ai_service.dart](../lib/services/ai_service.dart#L184-L185)

### 1.2 能力清单

| 方法 | 模型 | Thinking | maxTokens | 超时 | 说明 |
|------|------|----------|-----------|------|------|
| `splitTodo` | Flash | ❌ | 500 | 15s | 判断长文本是否需要拆分为多条 todo |
| `polishTodo` | Flash | ❌ | 200 | 15s | 将超长标题凝练到 2-18 字 |
| `generateProjectPlan` | **Pro** | ✅ | 3000 | 60s | 生成全部月计划卡 + 首日 todo |
| `generateDailyTodos` | Flash | ❌ | 500 | 30s | 根据当前月卡生成当天 todo |
| `streamChatMessages` | Flash | 可配置 | 16000 | 30s | 流式对话 + tool calling |
| `sendAgentLoop` | Flash | 可配置 | — | — | 多轮 agent loop（最多 5 轮） |
| `searchWeb` | — | — | — | 15s | Tavily 搜索（不走 LLM） |

---

## 2. 项目规划系统

### 2.1 核心概念

Sumi 的项目系统围绕"自学规划"设计。用户创建一个学习项目，AI 自动生成分阶段的月计划。

```
Project（项目）
  ├─ goal         目标描述（必填，触发 AI 规划的前置条件）
  ├─ level        当前水平（如"零基础"/"入门"/"进阶"）
  ├─ cycleMonths  规划周期（1-30 个月）
  ├─ timeConstraint 每周投入时间（小时）
  ├─ currentMonthIndex 当前进度（第几个月）
  │
  └─ MonthCard[]（月计划卡，数量 = cycleMonths）
       ├─ monthIndex   月份序号（0-based）
       ├─ title        AI 生成的月主题（5-15 字）
       ├─ summary      AI 生成的月摘要（30-100 字）
       └─ aiGenerated  是否由 AI 生成（用于重规划时清除）
```

### 2.2 创建项目 → AI 规划流程

```
用户点击"新建项目"
  │
  ▼
showProjectEditor()                      [project_editor.dart]
  填写：名称、颜色、目标、水平、周期、投入时间
  │
  ▼
store.addProject(...)                    [sumi_store_projects.dart:21]
  ├─ 创建 Project 对象
  ├─ 自动生成 cycleMonths 张空月卡（title='', summary=null）
  ├─ 设为当前项目
  └─ if (goal 非空) → _triggerPlanning(projId)    ← 异步，不阻塞 UI
                          │
                          ▼
              aiService.generateProjectPlan(       [ai_service.dart:527]
                goal, level, cycleMonths,
                timeConstraint, startDate
              )
              │  模型: Pro + Thinking
              │  输出: JSON → PlanResult
              │
              ▼
              PlanResult {
                monthPlans: [
                  { monthIndex: 0, title: "基础概念入门", summary: "..." },
                  { monthIndex: 1, title: "核心技能训练", summary: "..." },
                  ...
                ],
                todayTodos: [
                  { title: "完成第一章阅读", body: "...", date: "2026-07-14" }
                ]
              }
              │
              ▼
              更新月卡 ── 遍历 monthPlans →
                monthCardList[i].copyWith(
                  title: plan.title,
                  summary: plan.summary,
                  aiGenerated: true,
                )
              │
              ▼
              创建系统 todo ── 遍历 todayTodos →
                _addSystemTodoForDate(title, body, date, projectId)
                （带去重：同日同项目同标题不重复添加）
```

### 2.3 编辑项目 → 自动重规划流程

```
用户点击项目卡的"编辑"
  │
  ▼
showProjectEditor(context, store, project: p)   [project_editor.dart]
  修改目标/水平/周期/投入时间
  点击"保存"
  │
  ▼
store.updateProject(id, name, color, goal, level, cycleMonths, timeConstraint)
  │                                               [sumi_store_projects.dart:62]
  ├─ copyWith 更新 Project
  ├─ 若 cycleMonths 变化 → 增减月卡数量
  │   - 增加：追加空月卡
  │   - 减少：移除超出范围的月卡
  │
  └─ 检测 needsReplan:
        goal 变更      ≠ old.goal
        level 变更     ≠ old.level
        cycleMonths 变更 ≠ old.cycleMonths
        timeConstraint 变更 ≠ old.timeConstraint
      │
      ├─ 任一条件为 true 且 goal 非空
      │     │
      │     ▼
      │   retryPlanning(id)                      [sumi_store_projects.dart:331]
      │     ├─ 清除所有 aiGenerated=true 的月卡内容
      │     │   (title='', summary=null, aiGenerated=false)
      │     └─ await _triggerPlanning(id)        ← 同创建流程
      │
      └─ 条件不满足（只改了名字/颜色）
            → 不触发规划
```

### 2.4 AI 规划 Prompt 设计

> 完整 prompt 见 [ai_service.dart:204-235](../lib/services/ai_service.dart#L204-L235)

**System Prompt 核心要点：**

- **月计划**：每月一个主题（5-15 字）+ 摘要（30-100 字），摘要要高维度、战略性
- **递进关系**：各月之间基础 → 进阶 → 综合
- **首月特殊处理**：若起始月份剩余天数少，计划应紧凑
- **每日 Todo**：仅生成第一天的，基于第一个月计划拆解，1 条默认
- **时间约束**：考虑每周投入时间，不超出用户能力
- **输出格式**：严格 JSON，`monthPlans` + `todayTodos`

**User Prompt 输入：**
```
项目目标：{goal}
当前水平：{level}
规划周期：{cycleMonths} 个月
每周投入时间：{timeConstraint} 小时
起始日期：{startDate}
```

### 2.5 月卡展示逻辑

> 代码：[month_card_pager.dart](../lib/features/projects/month_card_pager.dart)

```
月卡列表（横向滑动，数量 = cycleMonths）
  │
  ├─ index ≤ currentMonthIndex → 已解锁 (_UnlockedCard)
  │     ├─ 当前月（index == currentMonthIndex）→ 柠檬色 accent
  │     ├─ 已过月 → 薄荷色 accent
  │     └─ 显示 title + summary（若 AI 已生成）
  │
  └─ index > currentMonthIndex → 锁定 (_LockedMonthCard)
        └─ 灰色锁图标，点击提示"前方的区域还没有开放"
```

**开发者开关**：`appSettings.showAllMonthCards` 可强制展示全部月卡（调试用）。

---

## 3. 每日 Todo 自动生成

### 3.1 触发时机

App 启动时 `SumiStore.create()` → `checkAndGenerateDaily()`。

### 3.2 生成流程

```
checkAndGenerateDaily()                     [sumi_store_projects.dart:216]
  │
  └─ 遍历所有 goal 非空的项目
       │
       ├─ 今天已有该系统 todo？ → 跳过
       │
       ├─ 当前月卡不存在？ → 创建基础 todo（"开始学习 {项目名}"）
       │
       ├─ 已过该月？ → advanceCurrentMonth() → 递归重试
       │
       └─ 正常流程：
            _generateDailyTodoForProject()
              │
              ├─ 计算本周已安排的 todo 数量（作为 load 代理）
              │
              ├─ 月卡标题为空？ → 降级基础 todo
              │
              └─ 调用 aiService.generateDailyTodos(
                    monthPlanTitle,    ← 当前月卡 title
                    monthPlanSummary,  ← 当前月卡 summary
                    date,              ← 今天日期
                    timeConstraint,    ← 项目每周投入时间
                    scheduledHours,    ← 本周已安排的 todo 数
                  )
                  │  模型: Flash，无 thinking
                  │
                  ▼
                  DailyTodoResult { todos: [{ title, body, date }] }
                  │
                  ├─ 成功 → 遍历创建系统 todo（带去重）
                  └─ 失败 → 降级基础 todo（"继续学习 {项目名}"）
```

### 3.3 降级策略

AI 生成失败时不会报错，而是静默降级为基础 todo：
- 无月卡 → `"开始学习 {项目名}"`
- 月卡为空 → `"开始学习 {项目名}"`
- API 失败 → `"继续学习 {项目名}"`

---

## 4. Agent Loop 对话系统

### 4.1 架构概览

```
用户输入
  │
  ▼
sendMessage(content)                        [sumi_store_chat.dart:136]
  ├─ 自动创建/复用会话
  ├─ 保存用户消息到 DB
  ├─ _buildMessagesContextForAgent()        ← 构建完整上下文
  │     ├─ System Prompt（含 MEMORY.md）
  │     ├─ 最近 60 条历史消息
  │     └─ 每条 assistant 传回 reasoning_content + tool_calls
  │
  └─ _streamAndPersistReply()               ← 执行 Agent Loop
        │
        ▼
        svc.sendAgentLoop(                   [ai_service.dart:772]
          messages, thinkingEnabled, executeTool,
          maxTurns: 5
        )
        │
        └─── loop (最多 5 轮) ───┐
          │                      │
          ▼                      │
          streamChatMessages()    │  [ai_service.dart:639]
          │  Flash + Thinking    │
          │  5 工具定义          │
          │  maxTokens: 16000   │
          │                      │
          ▼                      │
          StreamEvent:           │
          ├─ ContentDelta ──── 流式输出到 UI
          ├─ ReasoningDelta ── 思考过程（可折叠）
          ├─ ToolCallsComplete → 执行工具 → 追加结果 → 继续 loop ──┘
          └─ StreamDone（无 tool_calls）→ 结束
```

### 4.2 StreamEvent 类型

```dart
sealed class StreamEvent {}
class ContentDelta extends StreamEvent  { String text; }     // 文本增量
class ReasoningDelta extends StreamEvent { String text; }    // 思考过程增量
class ToolCallsComplete extends StreamEvent { List<ToolCall> calls; } // 工具调用完成
class StreamDone extends StreamEvent {}                      // 流结束
```

### 4.3 Agent Loop 消息序列规则

API 要求 `tool` 消息必须紧跟对应的 `assistant` 消息（含 `tool_calls`）。Agent loop 每轮的消息追加顺序：

```
1. assistant 消息（含 content + reasoning_content + tool_calls）
2. tool 消息（每个 tool_call 对应一条，含 tool_call_id）
3. 下一轮 assistant → tool → ...
4. 最后一轮 assistant 无 tool_calls → 结束
```

### 4.4 上下文窗口管理

```dart
// 最近 60 条消息
int startIndex = recentMessages.length > 60
    ? recentMessages.length - 60
    : 0;

// 安全保护：确保不以孤立的 tool 消息开头
while (startIndex > 0 && recentMessages[startIndex].role == 'tool') {
  startIndex--;
}
```

### 4.5 对话 System Prompt

> 完整 prompt：[sumi_store_chat.dart:402-446](../lib/store/sumi_store_chat.dart#L402-L446)

核心设计：
- **风格约束**：简洁直接，≤100 字，禁止 AI 套话
- **工具主动性**：用工具做对的事，不反复问用户
- **记忆注入**：MEMORY.md 完整内容嵌入 system prompt 末尾
- **归属规则**：默认描述 Sumi 自己，用户信息加 `用户：` 前缀

### 4.6 UI 状态映射

| Store 状态 | UI 表现 |
|-----------|---------|
| `isStreaming = true` | 输入框禁用，显示停止按钮 |
| `isThinking = true` | 聊天标题栏显示 "思考中…" |
| `currentToolCallLabel != null` | 标题栏显示工具执行状态（如 "搜索中…"） |
| `reasoningContent` 非空 | AI 气泡上方显示可折叠的思考过程 |

---

## 5. 工具系统

### 5.1 工具定义（OpenAI Function Calling Schema）

| 工具 | 用途 | 参数 |
|------|------|------|
| `search_web` | 搜索网络获取实时信息 | `query`: string |
| `read_memory` | 读取 MEMORY.md | 无 |
| `write_memory` | 写入 MEMORY.md | `content`: string |
| `read_todos` | 查询待办事项 | `filter`: "today" / "all" / "project:xxx" |
| `write_todo` | 创建待办事项 | `title`*, `date`, `projectId`, `body` |

> 定义位置：[ai_service.dart:247-335](../lib/services/ai_service.dart#L247-L335)

### 5.2 执行器

`ToolExecutor`（[tool_executor.dart](../lib/services/tool_executor.dart)）负责执行工具并返回字符串结果：

| 工具 | 实现 |
|------|------|
| `search_web` | 调用 Tavily Search API → 格式化为文本列表 |
| `read_memory` | 读取 `<app_documents>/sumi/MEMORY.md` → 截断至 3000 字符 |
| `write_memory` | 追加写入 MEMORY.md（带时间戳标题） |
| `read_todos` | 查询 `store.todoItems` → 格式化为 checklist 文本 |
| `write_todo` | 调用 `store.addSystemTodo()` → 返回确认 |

### 5.3 Tavily 搜索

> [ai_service.dart:589-630](../lib/services/ai_service.dart#L589-L630)

- API：`https://api.tavily.com/search`
- 参数：`search_depth: basic`, `max_results: 5`
- 返回：`[{title, url, content}]` 格式化列表
- Key 存储：`SecureSettingsStore` 加密存储

---

## 6. MEMORY.md 记忆系统

### 6.1 存储

- 路径：`<app_documents>/sumi/MEMORY.md`
- 格式：Markdown，与 Claude Code MEMORY.md 格式兼容
- 首次运行自动创建空文件

### 6.2 读写

```
读：System prompt 中注入完整内容
    对话开始时已加载，AI 不需要重复调用 read_memory

写：AI 通过 write_memory 工具追加
    每条记忆带时间戳标题：### 记忆 2026-07-14T10:30
    也可通过编辑器覆写整个文件
```

### 6.3 归属规则

System prompt 中的核心规则：
- MEMORY.md 默认记录 **Sumi 自己**的事
- 记录用户信息必须加 `用户：` 前缀
- 避免歧义：`喜欢简洁回复` → 谁喜欢？必须写 `用户：喜欢简洁回复`

### 6.4 写入时机（System Prompt 指导 AI）

1. 用户表达了长期偏好或习惯（非一次性请求）
2. 用户给了关于 Sumi 工作方式的反馈
3. 完成了里程碑式的任务
4. 出现了用户长期关注的主题或目标
5. 记忆中有过时或矛盾的内容需要更新

---

## 7. 数据模型

### 7.1 Project

```dart
class Project {
  String id;              // "proj-xxx"
  String name;            // 项目名称
  ProjectColor color;     // lemon/mint/lilac/cherry/sky/peach/sage
  String goal;            // 学习目标（空 = 不触发 AI 规划）
  String level;           // 当前水平
  int cycleMonths;        // 规划周期（月）
  int timeConstraint;     // 每周投入时间（小时），0 = 未设置
  int currentMonthIndex;  // 当前进度（0-based）
  DateTime createdAt;     // 创建时间
}
```

### 7.2 MonthCard

```dart
class MonthCard {
  String id;            // "mc-xxx"
  String projectId;     // 归属项目
  int monthIndex;       // 月份序号（0-based）
  String title;         // AI 生成的月主题
  String? summary;      // AI 生成的月摘要
  bool aiGenerated;     // AI 生成标记（重规划时用于清除）
}
```

### 7.3 ChatMessage（Agent Loop 扩展字段）

```dart
class ChatMessage {
  // ... 基础字段 ...
  String? reasoningContent;  // AI 思考过程（仅 assistant）
  String? toolCallsJson;     // 工具调用 JSON（仅 assistant）
  String? toolCallId;        // tool 消息关联的 tool_call_id（仅 tool）
}
```

### 7.4 PlanResult / DailyTodoResult

```dart
class PlanResult {
  List<MonthPlanItem> monthPlans;   // [{monthIndex, title, summary}]
  List<TodoSeed> todayTodos;        // [{title, body, date}]
}

class DailyTodoResult {
  List<TodoSeed> todos;             // [{title, body, date}]
}
```

---

## 8. 完整流程图

### 8.1 项目生命周期

```
┌─────────────────────────────────────────────────────────────────┐
│                        项目创建                                  │
│  showProjectEditor → addProject → _triggerPlanning              │
│                                    │                            │
│                    AI (Pro+Thinking) 生成月计划                   │
│                                    │                            │
│                    ┌───────────────┴───────────────┐            │
│                    ▼                               ▼            │
│              更新月计划卡                     创建首日 todo       │
│         (title+summary+aiGenerated)        (系统 todo，带去重)    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        日常使用                                  │
│                                                                 │
│  App 启动 → checkAndGenerateDaily()                             │
│    │                                                             │
│    ├─ 已有今日 todo → 跳过                                       │
│    ├─ 跨月 → advanceCurrentMonth() → 重新检测                    │
│    └─ 正常 → AI (Flash) 生成每日 todo                            │
│                                                                 │
│  用户手动 → advanceCurrentMonth() 推进进度                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        编辑重规划                                │
│                                                                 │
│  showProjectEditor (编辑) → updateProject                       │
│    │                                                             │
│    ├─ cycleMonths 变化 → 增减月卡                                │
│    └─ goal/level/周期/时间 变化 + goal 非空                       │
│          → retryPlanning                                        │
│            ├─ 清除旧 AI 月卡内容                                  │
│            └─ _triggerPlanning（同创建流程）                      │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 Agent Loop 时序

```
用户: "帮我搜一下 Rust 最新版本，然后记下来"
  │
  ▼
Turn 1: Assistant → ToolCallsComplete [search_web("Rust latest version")]
  │
  ▼
         Tool 结果: "Rust 1.85 于 2026-07-10 发布..."
  │
  ▼
Turn 2: Assistant → ToolCallsComplete [write_memory("Rust 最新稳定版为 1.85...")]
  │
  ▼
         Tool 结果: "已写入记忆。"
  │
  ▼
Turn 3: Assistant → ContentDelta "已搜索并记录，Rust 最新稳定版是 1.85..."
         → StreamDone（无 tool_calls）✓ 结束
```

### 8.3 文件索引

| 文件 | 职责 |
|------|------|
| [lib/services/ai_service.dart](../lib/services/ai_service.dart) | 所有 AI API 调用：规划、对话、拆分、搜索、Agent Loop |
| [lib/services/tool_executor.dart](../lib/services/tool_executor.dart) | 5 个工具的执行逻辑 |
| [lib/store/sumi_store.dart](../lib/store/sumi_store.dart) | 全局状态 + AI 初始化 + MEMORY.md 读写 |
| [lib/store/sumi_store_projects.dart](../lib/store/sumi_store_projects.dart) | 项目 CRUD + AI 规划触发 + 每日 todo 生成 |
| [lib/store/sumi_store_chat.dart](../lib/store/sumi_store_chat.dart) | 对话 CRUD + Agent Loop 消息构建 + System Prompt |
| [lib/models/models.dart](../lib/models/models.dart) | 全部数据模型 |
| [lib/features/projects/project_editor.dart](../lib/features/projects/project_editor.dart) | 项目新建/编辑弹窗 UI |
| [lib/features/projects/project_card.dart](../lib/features/projects/project_card.dart) | 项目信息卡（编辑/删除入口） |
| [lib/features/projects/month_card_pager.dart](../lib/features/projects/month_card_pager.dart) | 月卡横向滑动展示 |

# Sumi AI 与规划系统设计文档

> 最后更新：2026-07-15  
> 涵盖：AI 模型策略、Tool Calling、Agent Loop、项目规划全流程、目标评估、建议生成、每日 Todo 生成、MEMORY.md 记忆系统

---

## 目录

1. [AI 模型与能力矩阵](#1-ai-模型与能力矩阵)
2. [项目规划系统](#2-项目规划系统)
3. [目标评估系统](#3-目标评估系统)
4. [每日 Todo 自动生成](#4-每日-todo-自动生成)
5. [建议生成系统](#5-建议生成系统)
6. [Agent Loop 对话系统](#6-agent-loop-对话系统)
7. [工具系统](#7-工具系统)
8. [MEMORY.md 记忆系统](#8-memorymd-记忆系统)
9. [数据模型](#9-数据模型)
10. [完整流程图](#10-完整流程图)

---

## 1. AI 模型与能力矩阵

### 1.1 双模型策略

| 模型 | API 名称 | 用途 | Thinking | 原因 |
|------|----------|------|----------|------|
| **Flash** | `deepseek-v4-flash` | 日常对话、todo 拆分/润色、每日 todo 生成、建议生成、目标评估 | 对话可开关，其余关 | 速度快、成本低，适合高频轻量任务 |
| **Pro** | `deepseek-v4-pro` | 项目规划（基础版 + 增强版） | ❌ 关（与 `response_format: json_object` 冲突） | 规划需强推理能力，但 JSON 模式不能同时开 thinking |

> 代码位置：[ai_service.dart](../lib/services/ai_service.dart#L186-L187)

### 1.2 能力清单

| 方法 | 模型 | Thinking | maxTokens | 超时 | 说明 |
|------|------|----------|-----------|------|------|
| `splitTodo` | Flash | ❌ | 500 | 15s | 判断长文本是否需要拆分为多条 todo |
| `polishTodo` | Flash | ❌ | 200 | 15s | 将超长标题凝练到 2-20 字 |
| `generateProjectPlan` | Pro | ❌ | 32000 | 60s | 基础版：直接根据项目信息生成全部月计划卡 + 首日 todo |
| `generatePlanEnhanced` | Pro | ❌ | 32000 | 90s | 增强版：结合评估报告 + 领域知识生成计划 |
| `generateDailyTodos` | Flash | ❌ | 1000 | 30s | 根据当前月卡生成 1-3 条当天 todo |
| `generateSuggestions` | Flash | ❌ | 800 | 20s | 基于待办 + 记忆生成 3 条操作建议 |
| `assessGoal` | Flash | ❌ | 8000 | 60s | 对学习目标进行 8 维度评估（A/B/C/D 评定） |
| `streamChatMessages` | Flash | 可配置 | 32000 | 30s | 流式对话 + tool calling |
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
       ├─ summary      AI 生成的月摘要（30-120 字）
       └─ aiGenerated  是否由 AI 生成（用于重规划时清除）
```

### 2.2 规划双路径

系统支持两条规划路径：

| 路径 | 方法 | 触发方式 | 适用场景 |
|------|------|---------|---------|
| **基础规划** | `generateProjectPlan` | 直接调用 | 旧版入口，不经过评估 |
| **增强规划** | `GoalAssessor` → `generatePlanEnhanced` | 评估通过后 | 新版入口，先评估再规划 |

```
基础规划路径：
  _triggerPlanning(id)
    └─ aiService.generateProjectPlan(goal, level, cycleMonths, timeConstraint, startDate)
         └─ 直接规划（可选 Tavily 搜索上下文）

增强规划路径（06 轮新增）：
  GoalAssessor.assess(goal, level, cycleMonths, timeConstraint)
    ├─ searchWeb × N（多角度 Tavily 搜索）
    ├─ aiService.assessGoal(...)  → 8 维度评估，输出 A/B/C/D 评定
    └─ if verdict != D:
         aiService.generatePlanEnhanced(..., assessmentReport, domainKnowledge)
```

### 2.3 创建项目 → AI 规划流程

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

### 2.4 编辑项目 → 自动重规划流程

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

### 2.5 AI 规划 Prompt 设计

> 完整 prompt 见 [ai_service.dart](../lib/services/ai_service.dart) `_buildPlanningPrompt()` 方法

规划 prompt 已合并为一个 builder 方法，通过 `hasAssessment` 参数控制差异：

```dart
static String _buildPlanningPrompt({bool hasAssessment = false})
```

- `hasAssessment: false`（基础版）：4 条认知科学原则，不含评估反馈
- `hasAssessment: true`（增强版）：5 条原则，额外包含评估反馈 + 领域知识对齐

**System Prompt 核心要点（合并后）：**

- **难度递进**：每月难度递进 10-20%，内容应比用户当前水平稍难但通过努力可以完成
- **刻意练习**：每月必须有明确的核心技能目标 + 检验标准
- **时间约束**：∑每月预估小时 ≤ 周期月数 × 每周小时 × 4.3
- **评估反馈**（仅增强版）：如果评估报告指出问题，在计划中给出缓解策略
- **月计划**：每月一个主题（5-15 字）+ 摘要（30-120 字），摘要要高维度、战略性
- **递进关系**：各月之间基础 → 进阶 → 综合
- **每日 Todo**：仅生成第一天，基于第一个月计划拆解，1-2 条
- **领域对齐**：引用搜索到的具体资源和方法，不凭空编造
- **输出格式**：严格 JSON，`monthPlans` + `todayTodos`

**User Prompt 输入（基础版）：**
```
项目目标：{goal}
当前水平：{level}
规划周期：{cycleMonths} 个月
每周投入时间：{timeConstraint} 小时
起始日期：{startDate}
{可选：Tavily 搜索上下文}
```

**User Prompt 输入（增强版）：**
```
项目信息 + 评估报告（8 维度评分 JSON）+ 领域知识（多角度 Tavily 搜索结果）
```

### 2.6 月卡展示逻辑

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

## 3. 目标评估系统

### 3.1 概述

目标评估系统（06 轮新增）在规划前对用户的学习目标进行多维度诊断，决定是否允许进入规划阶段。

核心文件：
- [ai_service.dart](../lib/services/ai_service.dart) — `assessGoal()` 评估 API 调用
- [goal_assessor.dart](../lib/services/goal_assessor.dart) — `GoalAssessor` 编排多轮搜索 + 评估
- [plan_generator.dart](../lib/services/plan_generator.dart) — `PlanGenerator` 编排完整评估→规划流程

### 3.2 评估流程

```
GoalAssessor.assess(goal, level, cycleMonths, timeConstraint)
  │
  ├─ Phase 1: 多角度 Tavily 搜索
  │     ├─ searchWeb("{goal} 学习路线")
  │     ├─ searchWeb("{goal} 要学多久")
  │     └─ searchWeb("{goal} 最佳学习资源")
  │     └─ 汇总 → domainContext
  │
  ├─ Phase 2: AI 8 维度评估
  │     └─ aiService.assessGoal(goal, level, cycleMonths, timeConstraint, domainContext)
  │          模型: Flash，maxTokens: 8000，timeout: 60s
  │          │
  │          └─ 输出: GoalAssessment {
  │                clarity, feasibility, challengeFit, decomposability,
  │                timeRealism, motivationPotential, resourceAccess, measurability
  │                verdict: "a"/"b"/"c"/"d",
  │                concerns: [...], suggestions: [...],
  │                estimatedHours, domainSummary
  │            }
  │
  └─ Phase 3: 判定
       ├─ verdict == "d" → D 级（不可通过），展示原因和建议
       ├─ verdict == "c" → C 级（风险警告），用户确认后继续
       └─ verdict in ["a", "b"] → 进入 PlanGenerator 规划阶段
```

### 3.3 8 个评估维度

| 维度 | 说明 | 评分标准 |
|------|------|---------|
| `clarity` | 目标是否具体、可衡量 | 0.0-0.3 极度模糊 / 0.4-0.6 有方向不具体 / 0.7-1.0 具体可衡量 |
| `feasibility` | 物理/逻辑上是否可能 | D 级红线：物理不可能、无学习价值、极端困难、高度不确定 |
| `challengeFit` | 目标难度 vs 当前能力 | 参考心流理论，挑战略高于能力时最优（0.7-0.9） |
| `decomposability` | 能否拆为递进子目标 | 有清晰知识体系的学科高分，"提升品味"类模糊目标低分 |
| `timeRealism` | 时间投入是否足够 | 可用小时 < 行业共识最低时间 20% → D 级 |
| `motivationPotential` | 动机可持续性 | 是否与用户身份/长期发展关联，无明确线索给 0.5 |
| `resourceAccess` | 资源可达性 | 是否需特殊设备/导师，只需电脑网络 → 高分 |
| `measurability` | 进展可测性 | 有证书/作品/量化指标 → 高分 |

### 3.4 D 级判定规则

以下任一命中 → `verdict: "d"`，不可通过：

| subType | 含义 | 示例 |
|---------|------|------|
| `impossible` | 物理上不可能 | "造永动机" |
| `meaningless` | 无学习价值/过于简单 | "学好呼吸" |
| `extreme` | 能力极弱 + 目标极高 + 时间极短 | 小学数学 → 1 个月物理竞赛省一 |
| `too_uncertain` | 目标不可预测/不可控 | "拿诺贝尔奖" |

### 3.5 评估 UI

评估流程有专属的 Loading 页面和结果页面：

- **Loading 页**（`assessment_loading_page.dart`）：5 步进度（分析目标清晰度 → 搜索领域标准路径 → 校准能力匹配度 → 估算时间合理性 → 生成诊断报告）
- **结果页**（`assessment_result_page.dart`）：展示 8 维度雷达/评分、综合评定、关注点和建议

---

## 4. 每日 Todo 自动生成

### 4.1 触发时机

App 启动时 `SumiStore.create()` → `checkAndGenerateDaily()`。

### 4.2 生成流程

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
                  │  模型: Flash，maxTokens: 1000，无 thinking
                  │  System prompt: 根据月计划生成 1-3 条待办，当天已有足够待办时可返回空列表
                  │
                  ▼
                  DailyTodoResult { todos: [{ title, body, date }] }
                  │
                  ├─ 成功 → 遍历创建系统 todo（带去重）
                  └─ 失败 → 降级基础 todo（"继续学习 {项目名}"）
```

### 4.3 降级策略

AI 生成失败时不会报错，而是静默降级为基础 todo：
- 无月卡 → `"开始学习 {项目名}"`
- 月卡为空 → `"开始学习 {项目名}"`
- API 失败 → `"继续学习 {项目名}"`

---

## 5. 建议生成系统

### 5.1 概述

首页建议区采用**混合策略**：常驻固定建议 + AI 动态生成。

> 代码位置：[home_page.dart](../lib/features/home/home_page.dart) + [ai_service.dart](../lib/services/ai_service.dart) `generateSuggestions()`

### 5.2 混合策略

```
SuggestionStrip
  ├─ 固定建议（2 条，始终显示，不参与 AI 轮换）
  │     ├─ "建议以什么顺序开展我今天的待办"
  │     └─ "帮我总结一下今天的进展"
  │
  └─ AI 动态建议（2-3 条，每 90s 轮询更新）
        ├─ 基于今日待办具体内容生成
        ├─ 结合 MEMORY.md 用户记忆（个性化）
        └─ AI 不可用时降级为默认建议
              ├─ "我现在应该专注做什么"
              └─ "帮我回顾一下最近学了什么"
```

### 5.3 生成流程

```
_generateSuggestions()                           [home_page.dart]
  │
  ├─ 获取今日待办标题列表（按选中日期筛选）
  ├─ 读取 MEMORY.md → memory
  │
  ├─ aiService 为空？ → 固定 + 默认建议（不走 API）
  │
  └─ aiService.generateSuggestions(todayTodosText, memory)
       │  模型: Flash，maxTokens: 800，timeout: 20s
       │
       ├─ 成功返回 3 条 → 固定 + AI 建议
       └─ 失败/为空 → 固定 + 默认建议
```

### 5.4 轮询策略

- 间隔：**90 秒**（在 initState 中启动 `Timer.periodic`）
- 防重入：`_isGeneratingSuggestions` 标志位防止并发
- 安全退出：`mounted` 检查防止 setState 在 widget 销毁后调用

### 5.5 AI Prompt 设计

```
你是 Sumi。根据用户的待办列表，生成 3 条用户可能想让你执行的操作建议。

要求：
1. 每条是用户会对助手说的自然指令（如"帮我..."、"建议我..."、"总结..."）。
2. 必须基于今日待办的具体内容，不要泛泛而谈。
3. 每条 8-20 字。
4. 只输出 JSON：{"suggestions": ["建议1", "建议2", "建议3"]}
```

与旧版的关键区别：方向从「用户想问你的问题」→「用户想让你执行的操作建议」，去掉「像朋友求助」的社交拟人口吻。

---

## 6. Agent Loop 对话系统

### 6.1 架构概览

**会话模型**：按日历日期分组，每天一个独立会话。切换日期时自动加载该日对话。

```
用户输入（自由打字 or 点击建议 chip）
  │
  ▼
sendMessage(content, currentGreeting?)           [sumi_store_chat.dart]
  ├─ 记录问候语上下文（仅用于新日期会话首条消息）
  ├─ _getOrCreateConversationForDate(today)     ← 按日期查找/创建会话
  │     ├─ 同一天 → 复用已有会话
  │     └─ 跨天 → 自动创建新天会话
  ├─ 保存用户消息到 DB
  ├─ _buildMessagesContextForAgent()            ← 构建完整上下文
  │     ├─ System Prompt（含 MEMORY.md）
  │     ├─ 新会话首条 → 注入问候语上下文（如有）
  │     ├─ 最近 60 条历史消息
  │     └─ 每条 assistant 传回 reasoning_content + tool_calls
  │
  └─ _streamAndPersistReply()                   ← 执行 Agent Loop
        │
        ▼
        svc.sendAgentLoop(
          messages, thinkingEnabled, executeTool,
          maxTurns: 5
        )
        │
        └─── loop (最多 5 轮) ───┐
          │                      │
          ▼                      │
          streamChatMessages()    │
          │  Flash + Thinking    │
          │  5 工具定义          │
          │  maxTokens: 32000   │
          │                      │
          ▼                      │
          StreamEvent:           │
          ├─ ContentDelta ──── 流式输出到 UI
          ├─ ReasoningDelta ── 思考过程（可折叠）
          ├─ ToolCallsComplete → 执行工具 → 追加结果 → 继续 loop ──┘
          └─ StreamDone（无 tool_calls）→ 结束
```

### 6.2 日期驱动会话

会话不再通过列表管理，而是按日历日期自动分组。每天最多一个会话。

```
日历切换 → DateStrip 选中新日期
  │
  ▼
HomePage → store 读取 selectedDate
  │
  ▼
_getOrCreateConversationForDate(dateKey)
  ├─ 同一天且已有会话 → 直接复用
  ├─ 同一天无会话 → findConversationByDate(dateKey) 查 DB
  │     ├─ 找到 → 加载历史消息
  │     └─ 未找到 → createConversationForDate(dateKey) 新建
  └─ 不同天 → 切换会话，加载该日消息
```

关键字段：
- `_currentConversationId`：当前日期对应的会话 ID
- `_currentDateKey`：当前已加载的日期，用于判断是否需要切换
- `Conversation.dateKey`：DB 中存储的日期标识（`YYYY-MM-DD`）

### 6.3 StreamEvent 类型

```dart
sealed class StreamEvent {}
class ContentDelta extends StreamEvent  { String text; }     // 文本增量
class ReasoningDelta extends StreamEvent { String text; }    // 思考过程增量
class ToolCallsComplete extends StreamEvent { List<ToolCall> calls; } // 工具调用完成
class StreamDone extends StreamEvent {}                      // 流结束
```

### 6.4 Agent Loop 消息序列规则

API 要求 `tool` 消息必须紧跟对应的 `assistant` 消息（含 `tool_calls`）。Agent loop 每轮的消息追加顺序：

```
1. assistant 消息（含 content + reasoning_content + tool_calls）
2. tool 消息（每个 tool_call 对应一条，含 tool_call_id）
3. 下一轮 assistant → tool → ...
4. 最后一轮 assistant 无 tool_calls → 结束
```

### 6.5 上下文窗口管理

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

### 6.6 对话 System Prompt

> 完整 prompt：[sumi_store_chat.dart](../lib/store/sumi_store_chat.dart) `_chatSystemPrompt`

精简后的 prompt（~17 行，原 ~45 行）：

```
你是 Sumi，一个个人学习助手。风格：简洁直接，≤100 字，不用 AI 废话。

## 工具
你有搜索网络、读写记忆、管理待办的工具，需要时直接使用。

## 记忆（MEMORY.md）
已加载到上下文中，不需要重复读取。记录关于用户的信息时加「用户：」前缀。
遇到长期偏好、工作反馈、里程碑、长期目标时主动写入，不要每句话都记。
每条记忆简洁独立，写提炼后的事实而非流水账。

--- MEMORY.md ---
{memory}
--- END MEMORY.md ---
```

核心设计要点：
- **风格约束**：压缩为 1 行，保留「≤100 字 + 不用 AI 废话」两个关键约束
- **工具说明**：压缩为 1 行（工具定义已通过 API `tools` 参数传入，无需在 prompt 中详细描述）
- **记忆规则**：去掉详细示例（❌/✅），保留核心归属规则 + 写入时机
- **问候语上下文**：新日期会话的首条自由输入消息，末尾动态追加 `[上下文] 首页问候语："..."。请自行判断用户是否在回应它。`（仅一行，消费后立即清空，不传给后续消息）
- **Token 节省**：从约 450 字符 → 约 200 字符，每次对话节省 ~250 token

### 6.7 UI 状态映射

| Store 状态 | UI 表现 |
|-----------|---------|
| `isStreaming = true` | 输入框禁用，显示停止按钮 |
| `isThinking = true` | 聊天标题栏显示 "思考中…" |
| `currentToolCallLabel != null` | 标题栏显示工具执行状态（如 "搜索中…"） |
| `reasoningContent` 非空 | AI 气泡上方显示可折叠的思考过程 |

---

## 7. 工具系统

### 7.1 工具定义（OpenAI Function Calling Schema）

| 工具 | 用途 | 参数 |
|------|------|------|
| `search_web` | 搜索网络获取实时信息 | `query`: string |
| `read_memory` | 读取 MEMORY.md | 无 |
| `write_memory` | 写入 MEMORY.md | `content`: string |
| `read_todos` | 查询待办事项 | `filter`: "today" / "all" / "project:xxx" |
| `write_todo` | 创建待办事项 | `title`*, `date`, `projectId`, `body` |

> 定义位置：[ai_service.dart](../lib/services/ai_service.dart) `_chatTools`

### 7.2 执行器

`ToolExecutor`（[tool_executor.dart](../lib/services/tool_executor.dart)）负责执行工具并返回字符串结果：

| 工具 | 实现 |
|------|------|
| `search_web` | 调用 Tavily Search API → 格式化为文本列表 |
| `read_memory` | 读取 `<app_documents>/sumi/MEMORY.md` → 截断至 3000 字符 |
| `write_memory` | 追加写入 MEMORY.md（带时间戳标题） |
| `read_todos` | 查询 `store.todoItems` → 格式化为 checklist 文本 |
| `write_todo` | 调用 `store.addSystemTodo()` → 返回确认 |

### 7.3 Tavily 搜索

> [ai_service.dart](../lib/services/ai_service.dart) `searchWeb()`

- API：`https://api.tavily.com/search`
- 参数：`search_depth: basic`, `max_results: 5`
- 返回：`[{title, url, content}]` 格式化列表
- Key 存储：`SecureSettingsStore` 加密存储

---

## 8. MEMORY.md 记忆系统

### 8.1 存储

- 路径：`<app_documents>/sumi/MEMORY.md`
- 格式：Markdown，与 Claude Code MEMORY.md 格式兼容
- 首次运行自动创建空文件

### 8.2 读写

```
读：System prompt 中注入完整内容（通过 {memory} 占位符替换）
    对话开始时已加载，AI 不需要重复调用 read_memory
    建议生成系统也通过 store.readMemory() 读取以提供个性化建议

写：AI 通过 write_memory 工具追加
    每条记忆带时间戳标题：### 记忆 2026-07-15T10:30
    也可通过编辑器覆写整个文件
```

### 8.3 归属规则（已精简）

System prompt 中的核心规则（经精简后）：
- 记录关于用户的信息必须加 `用户：` 前缀
- 每条记忆简洁独立，写提炼后的事实而非流水账

> 注意：旧版 prompt 中的详细示例（❌/✅ 对比）已在精简中移除，以减少 token 消耗。AI 仍通过工具描述中的完整说明理解归属规则。

### 8.4 写入时机

System prompt 指导 AI 在以下情况主动写入：
1. 遇到长期偏好或习惯（非一次性请求）
2. 收到关于工作方式的反馈
3. 完成里程碑式任务
4. 出现长期关注的主题或目标

> 核心原则：不要每句话都记，只记"下次对话需要知道"的事。

---

## 9. 数据模型

### 9.1 Project

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

### 9.2 Conversation（按日期分组）

```dart
class Conversation {
  String id;            // "conv-xxx"
  String dateKey;       // 日期标识（format: "YYYY-MM-DD"），每天一个会话
  DateTime createdAt;
  DateTime updatedAt;
}
```

每个日历日期对应一个独立会话。切换到某天时自动查找或创建该日会话，加载其全部消息。不再有标题、置顶等手动管理功能。

### 9.3 MonthCard

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

### 9.4 ChatMessage（Agent Loop 扩展字段）

```dart
class ChatMessage {
  // ... 基础字段 ...
  String? reasoningContent;  // AI 思考过程（仅 assistant）
  String? toolCallsJson;     // 工具调用 JSON（仅 assistant）
  String? toolCallId;        // tool 消息关联的 tool_call_id（仅 tool）
}
```

### 9.5 GoalAssessment（评估结果，06 轮新增）

```dart
class GoalAssessment {
  // 8 维度评分（0.0-1.0）
  double clarity;
  double feasibility;
  double challengeFit;
  double decomposability;
  double timeRealism;
  double motivationPotential;
  double resourceAccess;
  double measurability;

  // 综合评定
  String verdict;         // "a" / "b" / "c" / "d"
  List<String> concerns;   // 关注点列表
  List<String> suggestions; // 可操作的调整建议
  String? estimatedHours;  // 预估总时长（如"约 200-300 小时"）
  String? domainSummary;   // 领域概述
}
```

### 9.6 PlanResult / DailyTodoResult

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

## 10. 完整流程图

### 10.1 项目生命周期

```
┌─────────────────────────────────────────────────────────────────┐
│                        项目创建                                  │
│  showProjectEditor → addProject                                 │
│    │                                                             │
│    ├─ 基础路径: _triggerPlanning                                │
│    │     └─ AI (Pro) → 生成月计划 + 首日 todo                    │
│    │                                                             │
│    └─ 增强路径: GoalAssessor → PlanGenerator                    │
│          ├─ Phase 1: 多角度 Tavily 搜索                          │
│          ├─ Phase 2: AI 8 维度评估 (Flash, 8000 tokens)         │
│          ├─ Phase 3: 判定 (D 驳回 / C 警告 / A-B 通过)          │
│          └─ Phase 4: AI (Pro) 结合评估+领域知识生成计划           │
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
│    └─ 正常 → AI (Flash, 1000 tokens) 生成 1-3 条每日 todo       │
│                                                                 │
│  日历切换 → _getOrCreateConversationForDate(dateKey)            │
│    ├─ 同一天 → 复用已有会话                                      │
│    └─ 跨天 → 加载/创建新天会话                                    │
│                                                                 │
│  首页建议区（每 90s 轮询）                                       │
│    ├─ 固定建议（2 条常驻）                                       │
│    └─ AI 动态建议 (Flash, 800 tokens，结合待办+记忆)              │
│                                                                 │
│  对话输入                                                       │
│    ├─ 自由输入 → 注入问候语上下文（新会话首条）                    │
│    └─ 点击建议 → 不注入问候语上下文                               │
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

### 10.2 对话生命周期

```
首页加载（某日期）
  │
  ▼
_getOrCreateConversationForDate("2026-07-15")
  ├─ DB 中已有该日会话 → 加载历史消息
  └─ DB 中无 → createConversationForDate("2026-07-15") 新建空会话
  │
  ▼
用户自由输入 "最近在学 Rust"
  │
  ▼
sendMessage("最近在学 Rust", currentGreeting: "最近在忙什么有趣的事？")
  ├─ [_activeGreeting = "最近在忙什么有趣的事？"]
  ├─ _buildMessagesContextForAgent()
  │     ├─ System Prompt（含 MEMORY.md）
  │     └─ + [上下文] 首页问候语："最近在忙什么有趣的事？"。请自行判断...
  └─ Agent Loop → AI 判断：用户在回应问候语 → 自然延续对话
```

### 10.3 Agent Loop 时序

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

### 10.4 文件索引

| 文件 | 职责 |
|------|------|
| [lib/services/ai_service.dart](../lib/services/ai_service.dart) | 所有 AI API 调用：规划、评估、对话、拆分、润色、建议、搜索、Agent Loop |
| [lib/services/goal_assessor.dart](../lib/services/goal_assessor.dart) | 目标评估编排器：多轮 Tavily 搜索 + AI 评估 |
| [lib/services/plan_generator.dart](../lib/services/plan_generator.dart) | 规划编排器：弹幕预设 + 评估→规划两阶段流程 |
| [lib/services/tool_executor.dart](../lib/services/tool_executor.dart) | 5 个工具的执行逻辑 |
| [lib/store/sumi_store.dart](../lib/store/sumi_store.dart) | 全局状态 + AI 初始化 + MEMORY.md 读写 |
| [lib/store/sumi_store_projects.dart](../lib/store/sumi_store_projects.dart) | 项目 CRUD + AI 规划触发 + 每日 todo 生成 |
| [lib/store/sumi_store_chat.dart](../lib/store/sumi_store_chat.dart) | 日期驱动会话 + Agent Loop 消息构建 + System Prompt + 问候语上下文 |
| [lib/data/chat_database.dart](../lib/data/chat_database.dart) | 聊天 DB：按日期查找/创建会话、消息 CRUD |
| [lib/models/models.dart](../lib/models/models.dart) | 全部数据模型（含 GoalAssessment、PlanResult 等） |
| [lib/features/home/home_page.dart](../lib/features/home/home_page.dart) | 首页：建议生成逻辑（混合策略 + 轮询）、问候语 |
| [lib/features/home/suggestion_strip.dart](../lib/features/home/suggestion_strip.dart) | 建议 chip 条 UI |
| [lib/features/projects/project_editor.dart](../lib/features/projects/project_editor.dart) | 项目新建/编辑弹窗 UI |
| [lib/features/projects/project_card.dart](../lib/features/projects/project_card.dart) | 项目信息卡（编辑/删除入口） |
| [lib/features/projects/month_card_pager.dart](../lib/features/projects/month_card_pager.dart) | 月卡横向滑动展示 |
| [lib/features/projects/assessment_loading_page.dart](../lib/features/projects/assessment_loading_page.dart) | 评估 Loading 页（5 步进度） |
| [lib/features/projects/assessment_result_page.dart](../lib/features/projects/assessment_result_page.dart) | 评估结果页（8 维度评分展示） |
| [lib/features/projects/planning_loading_page.dart](../lib/features/projects/planning_loading_page.dart) | 规划 Loading 页 |

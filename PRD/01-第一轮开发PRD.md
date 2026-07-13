# 01 — Sumi（米糖）第一轮开发 PRD

> **版本**：v1.0 · 2026-07-13  
> **本轮目标**：搭好本地数据骨架，完成事项首页 + 日历导航 + 项目/月卡 + 设置。  
> **不做**：AI 智能规划、米糖 Tab、用户系统、外观/语言切换。

---

## 1. 产品一句话

Sumi 是一个**本地优先的自学个人助手**。第一轮只做「能记、能看、能管项目上下文」的基础壳，智能规划留到后续轮次。

---

## 2. Tab 结构

第一轮仅 **2 个底部 Tab**：

```
┌──────────────┬──────────────┐
│    事项      │    设置      │   ← 底部导航栏
└──────────────┴──────────────┘
```

- **默认进入**：事项 Tab
- **项目切换/编辑**：不设独立 Tab，全部收在日历展开层内

---

## 3. 事项系统（首页）

### 3.1 布局总览

```
┌──────────────────────────────────┐
│  [日历导航 — 折叠态日期条]        │  ← 下拉展开月视图
├──────────────────────────────────┤
│                                  │
│   ┌──────┐  ┌────────────┐       │
│   │ 用户  │  │  系统 todo  │       │  Google Keep 风格不规则网格
│   │ todo  │  │ (淡黄/绿/紫)│       │
│   │ (白色) │  └────────────┘       │
│   └──────┘                       │
│   ┌──────────┐                   │
│   │   ...    │                   │
│   └──────────┘                   │
│                                  │
├──────────────────────────────────┤
│  [输入框 — 创建用户 todo]         │
└──────────────────────────────────┘
```

### 3.2 用户 Todo

| 属性 | 说明 |
|------|------|
| **来源** | 底部输入框直接创建 |
| **背景色** | 白色 `#FFFFFF` |
| **网格尺寸** | 按标题字数估算，参考 Keep masonry 布局（1×2 / 2×1 / 2×2） |
| **操作** | 点击切换完成态、长按删除、点击编辑标题 |
| **日期绑定** | 第一轮暂不绑定日期，全部展示在网格中 |

> **后续轮次**：输入字数 > 16 字时触发 AI 判断，识别用户意图是长 todo 还是应拆分为多条。

### 3.3 系统 Todo

| 属性 | 说明 |
|------|------|
| **来源** | 后续由项目系统 AI 规划产出；**第一轮仅支持手动创建测试数据** |
| **日期** | 不绑定日历日期，出现在事项网格全局池中 |
| **视觉区分** | 卡片左上角显示项目色点或项目名称 |

**背景色规则**（按所属项目）：

| 项目色 | 背景色 | 色值 |
|--------|--------|------|
| 柠檬黄 (lemon) | 淡黄 | `#FFF8E1` |
| 薄荷绿 (mint) | 淡绿 | `#E8F5E9` |
| 丁香紫 (lilac) | 淡紫 | `#F3E5F5` |
| 用户 todo | 白色 | `#FFFFFF` |

### 3.4 日历与 Todo 的关系（第一轮）

- 日历**不做按日筛选**，日期条仅作为「展开月视图 / 项目上下文」的入口
- 日历日期底部小点留字段，第一轮不实现
- 后续再打通「选中日期 → 筛选该日用户 todo」

---

## 4. 日历导航

> **设计参考**：仅借鉴 Classugar 的交互骨架，不复制其签到、拖拽、语音、AI 等业务逻辑。风格要求：**扁平简洁，不做高保真**。

### 4.1 Classugar 参考对照

| Classugar 组件 | Sumi 借鉴点 |
|---------------|------------|
| `_DateStrip` | 横向日期 chip、选中居中滚动、左右渐变遮罩 |
| `_ScheduleHeaderCard` | 下滑手势展开月视图 |
| `_MonthCalendar` | 当月 7 列网格 |
| `_ProjectTabs` | 最多 3 项目、lemon/mint/lilac 三色 |
| `_GoalHeader` | 可折叠项目卡 |
| `_MonthPlanPager` + `_LockedMonthCard` | 横向月卡滑动、未解锁锁定态 |

### 4.2 两层缩放

**折叠态（事项页顶部）**

- 横向日期条：当月每天一个 chip，选中项居中，左右渐变遮罩
- 底部拖拽条 / 下滑手势 → 展开月视图
- 第一轮日期选中暂不做筛选功能，仅保留交互骨架

**展开态（月视图）**

- 上滑 / 点关闭 → 收回折叠态
- 内容自上而下：
  1. **当月完整日历**（7 列网格）
  2. **项目 Tab 栏**（当前项目高亮，最多 3 个）
  3. **项目卡**（可折叠展开：目标 / 水平 / 周期 / 约束·投入时间）
  4. **当前项目的月卡横向 pager**

### 4.3 月卡锁定规则

- 每个项目有 `cycleMonths`（周期月数）和 `currentMonthIndex`（已解锁月索引，0-based）
- `monthIndex <= currentMonthIndex` → 展示月卡内容
- `monthIndex > currentMonthIndex` → 锁定卡
- **锁定文案**：「前方的区域还没有开放，过段时间再来探索吧」
- 点击锁定卡弹窗提示即可，无需复杂动画

---

## 5. 项目系统

### 5.1 约束

| 规则 | 说明 |
|------|------|
| **数量上限** | 最多 **3** 个项目同时进行 |
| **颜色** | 固定三选一：`lemon` / `mint` / `lilac` |
| **切换入口** | 仅在月视图展开层的项目 Tab 内切换 |

### 5.2 项目字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 项目名称 |
| `color` | enum | lemon / mint / lilac |
| `goal` | string | 目标 |
| `level` | string | 当前水平（用户自评/描述） |
| `cycleMonths` | number | 周期（月数） |
| `timeConstraint` | string | 投入时间约束（如「每天 1h」「周末 3h」） |
| `currentMonthIndex` | number | 当前解锁月索引（0-based） |

### 5.3 月卡字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `projectId` | string | 所属项目（FK → Project） |
| `monthIndex` | number | 第几月（0-based） |
| `title` | string | 月卡标题 |
| `summary` | string? | 月卡摘要（可选） |

### 5.4 级联删除

删除项目时，**一并删除**：
1. 该项目下所有月卡（MonthCard）
2. 该项目下所有系统 todo（`source = system`）

用户 todo（`source = user`）**不受影响**。

### 5.5 第一轮项目操作

- ✅ 新建项目（校验 ≤3）
- ✅ 编辑项目卡字段
- ✅ 删除项目（确认弹窗 + 级联删除）
- ✅ 手动新建 / 编辑 / 删除月卡
- ❌ AI 生成月卡
- ❌ AI 生成系统 todo

---

## 6. 设置系统

| 项 | 第一轮 |
|----|--------|
| DeepSeek API Key | ✅ 录入 + 安全存储 |
| Tavily API Key | ✅ 录入 + 安全存储 |
| 模型选择 | 不在 UI 暴露；代码内预留 `plannerModel = deepseek-v4-pro`、`defaultModel = deepseek-v4-flash` |
| Clear Data | ✅ 清除项目 / 月卡 / todo / 用户偏好；**保留 API Key** |
| 外观（日间/夜间/跟随系统） | ❌ 写死浅色扁平 |
| 语言切换 | ❌ 仅中文 |
| 行为日志 | ❌ |

---

## 7. 数据模型

```typescript
// 概念 schema，实现语言不限

enum TodoSource { user, system }
enum ProjectColor { lemon, mint, lilac }

interface AppSettings {
  deepseekApiKey: string
  tavilyApiKey: string
  plannerModel: string   // 预留：deepseek-v4-pro
  defaultModel: string   // 预留：deepseek-v4-flash
}

interface Project {
  id: string
  name: string
  color: ProjectColor
  goal: string
  level: string
  cycleMonths: number
  timeConstraint: string
  currentMonthIndex: number
  createdAt: string  // ISO8601
}

interface MonthCard {
  id: string
  projectId: string      // FK → Project，级联删除
  monthIndex: number
  title: string
  summary?: string
}

interface TodoItem {
  id: string
  source: TodoSource
  projectId?: string     // system todo 必填；user todo 为 null
  date?: string          // ISO8601，预留字段，第一轮不使用
  title: string
  body?: string
  done: boolean
  createdAt: string      // ISO8601
}

// 应用快照
interface AppSnapshot {
  settings: AppSettings
  projects: Project[]
  monthCards: MonthCard[]
  todos: TodoItem[]
  currentProjectId?: string
  selectedDate: string     // 日历 UI 状态
  monthViewExpanded: boolean
}
```

### 存储方案

- 本地优先，单 JSON snapshot 或 SQLite 均可
- API Key 走安全存储（secure storage），不进入 snapshot 明文

---

## 8. 推荐代码结构

```
sumi/
├── PRD/
│   └── 01-第一轮开发PRD.md
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── sumi_app.dart          # MaterialApp + 主题
│   │   └── main_shell.dart        # 2 Tab：事项 / 设置
│   ├── features/
│   │   ├── todos/
│   │   │   ├── todo_grid.dart     # Keep 风格网格
│   │   │   ├── todo_card.dart
│   │   │   └── todo_input.dart
│   │   ├── calendar/
│   │   │   ├── date_strip.dart    # 折叠态日期条
│   │   │   ├── month_view.dart    # 展开层容器
│   │   │   └── month_calendar.dart
│   │   ├── projects/
│   │   │   ├── project_tabs.dart
│   │   │   ├── project_card.dart  # 可折叠项目卡
│   │   │   ├── month_card_pager.dart
│   │   │   └── project_editor.dart
│   │   └── settings/
│   │       └── settings_page.dart
│   ├── models/
│   ├── stores/
│   │   └── sumi_store.dart        # ChangeNotifier，按 domain 拆 part 文件
│   ├── data/
│   │   ├── repository.dart        # CRUD + 级联删除
│   │   └── snapshot_store.dart
│   └── services/
│       ├── ai_service.dart        # 第一轮为空壳/stub
│       └── tavily_service.dart    # 第一轮为空壳/stub
```

---

## 9. 后续轮次接口预留

| 后续能力 | 第一轮预留 |
|----------|-----------|
| AI 项目规划 → 系统 todo | `TodoItem.source = system`、`projectId`、Repository 批量写入 |
| >16 字 todo 智能拆分 | `AiService.splitTodo(text)` stub |
| 系统 todo 绑定日期 | `TodoItem.date` 字段 |
| 米糖 Tab | `features/sumi/` 目录占位，不加 Tab |
| 日历按日筛选 todo | `selectedDate` + `todosForDate()` 方法 |
| 用户系统（名片/成就/记忆） | 数据模型预留，UI 不做 |

---

## 10. 验收清单

- [ ] 2 Tab 底部导航：事项 / 设置，默认进入事项
- [ ] 输入框创建用户 todo → Keep 风格网格展示 → 完成/删除
- [ ] 可手动创建系统 todo → 按项目色显示（淡黄/淡绿/淡紫）
- [ ] 日历条折叠态 + 下拉展开月视图 + 上滑收回
- [ ] 月视图内：完整日历、项目 Tab（≤3）、项目卡可折叠编辑、月卡横向 pager、锁定态
- [ ] 新建 / 编辑 / 删除项目 → 级联删除月卡与系统 todo
- [ ] 设置页：API Key 录入保存、Clear Data（保留 Key）
- [ ] 全功能无 AI 网络调用（AiService 均为 stub）
- [ ] 无米糖 Tab、无用户系统 UI
- [ ] 仅中文、仅浅色扁平主题

---

## 11. 设计原则

1. **扁平简洁** — 不做高保真，交互清晰优先
2. **一个 Store，多文件拆分** — 避免单文件膨胀
3. **Repository 负责级联删除** — 不在 UI 层散落删除逻辑
4. **只移植日历导航交互骨架** — 不移植 Classugar 业务状态机
5. **AI 能力后置** — 第一轮先把本地数据流跑通

---

*文档版本：v1.0 · 2026-07-13*

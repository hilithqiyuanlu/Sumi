# 02 — Sumi（米糖）第二轮开发 PRD

> **版本**：v1.0 · 2026-07-13  
> **本轮目标**：打通 DeepSeek API，实现 >16 字 todo 智能拆分，让 AI 首次介入产品流程。  
> **不做**：米糖 Tab 对话、项目 AI 规划、系统 todo 自动生成。

---

## 1. 与第一轮的关系

| 01 已交付 | 02 改动 |
|-----------|---------|
| AiService 空壳 stub | **→ 实现**：真实调用 DeepSeek API |
| 输入框创建 todo（无上限） | **→ 升级**：>16 字触发 AI 拆分判断 |
| 设置页 API Key 已录入 | 本次直接复用 |

其余模块（事项网格、日历、项目系统、设置页）本轮不涉及。

---

## 2. 功能详述

### 2.1 AI 基础接入层

**`AiService` 不再为空壳**，实现以下能力：

| 方法 | 模型 | 说明 |
|------|------|------|
| `splitTodo(text)` | `deepseek-v4-flash` | 判断长文本是单条 todo 还是多条，返回拆分结果 |
| `chat(prompt)` | `deepseek-v4-flash` | 预留：基础对话能力（本轮实现但不接入 UI） |

**技术细节**：
- 使用 `http` 包直连 DeepSeek API（`https://api.deepseek.com/v1/chat/completions`）
- 从 `SumiStore.appSettings` 读取 API Key（非安全存储直读，通过 store 注入）
- 非流式调用（todo 拆分场景不需要 streaming）
- 超时 15s，失败返回原始文本（降级为直接创建单条 todo）
- 不在 UI 暴露模型选择

### 2.2 Todo 智能拆分

**触发条件**：用户在输入框提交文本，字数 **> 16**（中文字符 `.length > 16`）

**流程**：

```
用户输入 >16 字 → 点击发送
  ↓
弹出「AI 分析中…」加载态（非阻塞，约 1-3s）
  ↓
AI 返回判断结果：
  ├── 单条 todo：「这是一个较长的 todo，已直接添加」
  │     → 创建 1 条用户 todo，标题为原文
  │
  └── 多条 todo：「已拆分为 N 条」
        → 展示拆分列表（checkbox 样式，默认全选）
        → 用户可取消勾选某几条
        → 点「确认添加」批量创建
```

**AI Prompt 设计要点**：
- System prompt：明确 Sumi 是自学助手，todo 尽可能独立可执行
- 返回 JSON 格式：`{ "split": true/false, "items": ["todo1", "todo2"] }`
- 拆分规则：语义独立、可单独完成、保留原意

**降级策略**：
- API 超时 → 原文直接创建为 1 条 todo
- API 返回格式异常 → 原文直接创建为 1 条 todo  
- 网络不可用 → 原文直接创建为 1 条 todo
- 降级时 toast 提示「网络异常，已直接添加」

**不触发拆分的情况**：
- 字数 ≤ 16 → 行为与 01 完全一致，直接创建
- API Key 未设置 → 直接创建 + toast「请先在设置中配置 API Key」

### 2.3 UI 改动

只涉及事项页的输入区域和新增的拆分确认组件：

| 组件 | 改动 |
|------|------|
| `TodoInput` | 发送时判断字数，>16 走 AI 流程 |
| **新增** `SplitConfirmSheet` | 底部弹出面板，显示拆分结果列表 + 确认/取消 |
| **新增** `AiLoadingIndicator` | 小型的加载动效（文本 + 点点点动画） |

### 2.4 不做的

- ❌ 米糖 Tab（对话界面）
- ❌ 项目 AI 规划
- ❌ 系统 todo 自动生成
- ❌ streaming 响应（本轮统一非流式）
- ❌ AI 对话记忆/上下文

---

## 3. 架构改动

### 3.1 AiService 重构

```
旧：lib/services/ai_service.dart  — 空壳 stub
新：lib/services/ai_service.dart  — 实现 DeepSeek HTTP 调用
```

```dart
class AiService {
  final String apiKey;
  final http.Client _client;

  AiService({required this.apiKey});

  /// Todo 拆分：判断长文本是否应拆为多条。
  /// 返回 null 表示降级（直接使用原文）。
  Future<SplitResult?> splitTodo(String text) async { ... }

  /// 预留：对话。
  Future<String> chat(String prompt) async { ... }
}

class SplitResult {
  final bool split;        // 是否需要拆分
  final List<String> items; // 拆分后的 todo 列表
}
```

### 3.2 Store 改动

`SumiStore` 增加 `AiService?` 引用：

- `_aiService` 字段，在 `create()` 工厂中根据 API Key 是否存在决定是否初始化
- API Key 更新时同步重建 `_aiService`
- 新增 `splitAndAddTodo(String text)` 方法：协调 AI 调用 + 创建 todo

### 3.3 数据模型不变

`models.dart` 无改动。拆分后的 todo 就是普通的 `TodoItem(source: user)`。

---

## 4. 文件清单

### 新增文件（3 个）

```
lib/features/todos/
├── split_confirm_sheet.dart   # 拆分确认底部弹窗
└── ai_loading_widget.dart     # AI 分析加载态

lib/services/
└── ai_service.dart            # 重写：从 stub 升级为真实实现
```

### 修改文件（4 个）

```
lib/store/sumi_store.dart      # +_aiService 字段，+splitAndAddTodo()
lib/features/todos/todo_input.dart  # >16 字走 AI 流程
lib/main.dart                  # AiService 初始化传入 store
pubspec.yaml                   # +http 依赖（已在 01 末添加）
```

---

## 5. Prompt 设计

### System Prompt

```
你是 Sumi（米糖），一个自学个人助手的 AI 引擎。
你的任务是将用户输入的长文本智能拆分为独立可执行的 todo 事项。

规则：
1. 如果文本描述的是单一事项（尽管很长），不要拆分。
2. 如果包含多个独立步骤或事项，拆分为独立 todo。
3. 每条 todo 保留完整的语义，可脱离上下文理解。
4. 拆分后每条 2-20 字为宜。
5. 以 JSON 格式回复，不要带任何额外文字。

回复格式：
{"split": true/false, "items": ["事项1", "事项2"]}
```

### 示例

| 输入 | 输出 |
|------|------|
| 「明天下午三点去图书馆借一本线性代数的教材」（19 字） | `{"split": false, "items": ["明天下午三点去图书馆借一本线性代数的教材"]}` |
| 「复习线代第三章做课后习题然后整理错题本再预习第四章」（26 字） | `{"split": true, "items": ["复习线代第三章", "做课后习题", "整理错题本", "预习第四章"]}` |

---

## 6. 验收清单

- [ ] 设置页配置 DeepSeek API Key 后，输入 >16 字触发 AI 拆分
- [ ] AI 判断为单条时，直接创建，无多余弹窗
- [ ] AI 判断为多条时，弹出拆分确认面板
- [ ] 拆分面板可取消勾选部分条目
- [ ] 无 API Key 时，>16 字仍然直接创建 + toast 提示
- [ ] 网络异常 / 超时时降级为直接创建 + toast 提示
- [ ] ≤16 字行为与 01 完全一致（无 AI 调用）
- [ ] 拆分后的 todo 为普通用户 todo，可正常完成/删除/编辑
- [ ] 无 streaming、无米糖 Tab、无项目 AI 规划

---

## 7. 后续轮次展望

| 能力 | 状态 |
|------|------|
| 米糖 Tab — 自由对话 | 03 候选 |
| 项目 AI 规划 → 系统 todo | 03 候选 |
| 日历按日筛选 todo | 03 候选 |
| streaming 响应 | 03 候选 |

---

*文档版本：v1.0 · 2026-07-13*

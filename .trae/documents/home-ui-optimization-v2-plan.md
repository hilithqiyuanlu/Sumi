# 首页 UI/UX 优化 V2 开发计划

## Summary

本轮优化聚焦用户最新反馈：修复设置界面 Switch 颜色与苏米记忆入口、调整日历导航栏避免与灵动岛冲突、重构输入框为悬浮样式并增加 Sumi/Todo 双模式切换、调整首页打开逻辑为每次新建空会话、在历史会话侧边栏增加新建能力。文案保持"尽管说"不变。

## Current State Analysis

### 1. 设置界面（`lib/features/settings/settings_body.dart`）

- 当前只有 API 密钥、"披露全部月卡"开关、数据清除三个区域。
- `Switch` 使用 `AppTheme.light()` 中定义的主题色：selected track 为 `primary500.withValues(alpha: 0.38)`，thumb 为白色，整体观感偏灰。
- 苏米记忆相关功能在 `lib/features/chat/wrench_panel.dart` 中，通过首页右上角扳手按钮打开，尚未整合进设置界面。
- 首页右上角扳手按钮在 `lib/features/home/home_page.dart` 的 `_buildToolsButton()` 中。

### 2. 日历导航栏（`lib/features/calendar/date_strip.dart` + `lib/features/home/home_page.dart`）

- `DateStrip` 已去卡片化，但 `HomePage` 中对其使用 `EdgeInsets.symmetric(vertical: s8)`，顶部紧贴状态栏/灵动岛。
- `DateStrip` 自身没有处理 `SafeArea` 或状态栏避让。

### 3. 输入框区域（`lib/features/chat/chat_input.dart` + `lib/features/home/suggestion_strip.dart`）

- `ChatInput` 外层仍有 `Container(color: surfaceAlt, border.top)` 作为底栏背景，导致"悬浮感"不足。
- 内部 TextField 容器带白色背景 + 边框，视觉上与底栏背景叠加，显得厚重。
- 没有模式切换按钮；当前输入统一走 `onSend` 发送到对话。
- `SuggestionStrip` 当前上下 padding 为 `s8`，与输入框之间存在可见间隙。

### 4. 首页打开逻辑（`lib/store/sumi_store.dart`）

- `SumiStore.create()` 中调用 `loadConversations()` 加载历史列表，但没有主动创建/恢复当前会话。
- `main.dart` 也没有调用 `ensureLastConversation()`。
- `sendMessage()` 内部会在 `currentConversationId == null` 时自动创建新会话，但首页空状态会显示为"无消息"，而不是用户期望的固定提示语。

### 5. 历史会话侧边栏（`lib/features/home/side_drawer.dart`）

- 当前只展示会话列表，支持长按置顶/重命名/删除，但没有"新建会话"入口。
- `SumiStore.createConversation()` 已存在，可直接复用。

### 6. 空状态文案（`lib/features/home/home_page.dart`）

- 当前显示"嗨 {name}，今天要和 Sumi 一起做点什么"，且带 Icon。
- 用户要求 Sumi 模式下改为"Hi, (name)"。

## Proposed Changes

### 1. 设置界面改造

**文件 1: `lib/features/settings/settings_body.dart`**

- **What**: 在"开发者"与"数据管理"之间新增"苏米记忆"区域。
- **How**:
  - 初始状态为折叠/只读卡片：显示记忆内容前 2~3 行摘要，超出时显示省略号。
  - 卡片右下角放置"编辑"按钮；点击后展开为大文本输入框（类似 wrench_panel）。
  - 编辑状态下显示"保存"和"清空记忆"操作。
  - 状态保存调用 `store.readMemory()` 与 `store.writeMemory()`。
- **Why**: 用户不希望记忆做成入口按钮，而是直接内嵌在设置中；同时又不希望一上来就是大编辑框。

**文件 2: `lib/theme/app_theme.dart`**

- **What**: 修复 Switch 主题色，使其不发灰。
- **How**:
  - selected track: `primary500`（去掉 alpha 0.38 的半透明灰感）。
  - unselected track: `neutral300` 或 `neutral200`（明确关闭态）。
  - thumb: 保持白色；disabled 时保持 `neutral200`。
  - 如果仍显灰，可在 `Switch` 上显式设置 `activeColor`、`activeTrackColor`、`inactiveThumbColor`、`inactiveTrackColor`。
- **Why**: 当前 alpha 0.38 的轨道色导致开关看起来是"半禁用"状态。

**文件 3: `lib/features/home/home_page.dart`**

- **What**: 移除首页右上角扳手工具按钮（`_buildToolsButton()`）。
- **Why**: 工具功能中的核心"苏米记忆"将迁移到设置界面，首页不再需要这个入口。

### 2. 日历导航栏顶部避让

**文件: `lib/features/home/home_page.dart`**

- **What**: 给日历导航栏顶部增加安全区域 padding。
- **How**: 将 `DateStrip` 所在 `Padding` 改为：
  ```dart
  Padding(
    padding: EdgeInsets.only(
      left: s16,
      right: s16,
      top: MediaQuery.of(context).padding.top + s8,
      bottom: s8,
    ),
    child: DateStrip(onExpandMonth: _openMonthView),
  )
  ```
- **Why**: 避免日期条被 iPhone 灵动岛/状态栏遮挡，同时保留与下方待办区的原有间距。

### 3. 输入框区域重构

**文件 1: `lib/features/chat/chat_input.dart`**

- **What**: 移除底栏背景容器，改为悬浮输入框；增加 Sumi/Todo 模式切换圆形按钮；修复发送按钮与"丑框"问题。
- **How**:
  - 删除外层 `Container` 的 `color` 与 `border.top`，仅保留水平 padding 和 bottom safearea。
  - 在 TextField 左侧增加圆形模式切换按钮（直径 32px）。
    - Sumi 模式：图标为 `chat_bubble` 或 `smart_toy`，主色调。
    - Todo 模式：图标为 `check_circle` 或 `task_alt`，可改为 accent/coral 色以作区分。
  - 根据模式切换：
    - placeholder：Sumi 模式"尽管说"；Todo 模式"添加待办事项"。
    - 发送/确认按钮图标可区分：Sumi 用 send，Todo 用 add_task。
    - 输入框边框/背景色细微变化（例如 Todo 模式使用 accent100/accent500 暗示）。
  - 在 `ChatInput` 中新增 `InputMode mode` 状态与 `onModeChanged` 回调，或直接在内部管理并通知父级。
  - 发送逻辑：
    - Sumi 模式：调用 `widget.onSend(text)`。
    - Todo 模式：调用 `widget.onAddTodo(text)`；若 `text.length > 16`，调用 `store.splitAndAddTodo(text)` 触发凝练/拆分；否则直接调用 `store.addTodoByTitle(text)`。
  - 保留现有长按语音逻辑，但仅在 Sumi 模式下生效；Todo 模式下禁用语音。
- **Why**: 这是本轮最大改动，满足用户在"尽管说"左侧切换模式、且 Todo 模式下触发原有 AI 拆分/凝练逻辑的需求。

**文件 2: `lib/features/home/home_page.dart`**

- **What**: 在 `HomePage` 中管理输入模式状态，并传给 `ChatInput`。
- **How**:
  - 添加 `_inputMode` 状态（enum `InputMode { chat, todo }`）。
  - 将 `ChatInput` 调用改为：
    ```dart
    ChatInput(
      mode: _inputMode,
      onSend: store.sendMessage,
      onAddTodo: _handleAddTodo,
      voiceService: _inputMode == InputMode.chat ? store.voiceService : null,
    )
    ```
  - `_handleAddTodo(String title)` 中判断长度，调用 `store.addTodoByTitle` 或 `store.splitAndAddTodo`。
- **Why**: 父级持有模式状态，便于根据模式更新其他 UI（如空状态文案）。

**文件 3: `lib/features/home/suggestion_strip.dart`**

- **What**: 让建议胶囊更紧贴输入框。
- **How**: 将 `Padding` 改为 `EdgeInsets.only(left: s16, right: s16, top: s4, bottom: s4)`。
- **Why**: 减少建议区与输入框之间的视觉间隙。

### 4. 首页打开逻辑调整

**文件: `lib/store/sumi_store.dart`**

- **What**: 应用启动后自动创建一个新的空会话，而不是恢复上一次未完成的对话。
- **How**: 在 `SumiStore.create()` 的 `loadConversations()` 之后调用 `createConversation()`。
- **Why**: 用户要求每次打开都显示固定提示语"今天一起做点什么？"，这意味着需要一个空的当前会话。

### 5. 历史会话侧边栏增加新建

**文件: `lib/features/home/side_drawer.dart`**

- **What**: 在会话列表顶部增加"新建会话"按钮。
- **How**:
  - 在 `_buildConversationList` 的 `ListView` 顶部添加一个 `ListTile` 或按钮：
    ```dart
    ListTile(
      leading: const Icon(Icons.add, color: primary500),
      title: const Text('新建会话'),
      onTap: () {
        store.createConversation();
        onClose();
      },
    )
    ```
  - 点击后调用 `store.createConversation()` 并关闭侧边栏。
- **Why**: 用户明确需要在历史会话区域新建会话。

### 6. 空状态文案调整

**文件: `lib/features/home/home_page.dart`**

- **What**: Sumi 对话模式下空状态显示"Hi, (name)"，不带 icon。
- **How**: 修改 `_buildEmptyState`：
  - 移除 Icon。
  - 文案改为 `'Hi${userName.isEmpty ? '' : ', $userName'}'`。
- **Why**: 用户要求该模式下文案简洁。

### 7. 固定提示语

**文件: `lib/features/home/home_page.dart`**

- **What**: 无论是否有 name，首页打开后空状态显示"今天一起做点什么？"。
- **How**: 将固定提示语作为副标题或主标题下方的说明文字。
  - 主文案："Hi, (name)"
  - 副文案："今天一起做点什么？"
- **Why**: 满足用户"每次打开都显示固定提示语"的需求。

## Assumptions & Decisions

1. **苏米记忆的"只读展示"形态**：采用折叠卡片形式，默认显示 2~3 行摘要，点击"编辑"后展开为大输入框。如果摘要为空则显示"暂无记忆"。
2. **Todo 模式 >16 字的触发逻辑**：直接复用已有的 `SumiStore.splitAndAddTodo(String)`。该方法内部会调用 AI 进行凝练/拆分。若 AI 不可用，则降级为直接创建一个 todo。
3. **模式切换状态**：由 `HomePage` 管理并透传给 `ChatInput`，便于后续根据模式影响空状态或其他区域。
4. **语音输入**：仅在 Sumi 模式下可用；Todo 模式下禁用长按语音，但保留普通键盘输入。
5. **首页新建空会话**：每次应用启动创建新会话，历史中的旧会话保留；空会话没有用户消息，不会污染历史。
6. **文案"尽管说"保持不变**：不按截图改为"尽管问"。
7. **建议胶囊**：仍保持横向滚动，仅调整与输入框的间距。

## Files to Modify

| 文件 | 主要改动 |
|------|----------|
| `lib/features/settings/settings_body.dart` | 新增苏米记忆折叠卡片、修复 Switch 显式颜色 |
| `lib/theme/app_theme.dart` | 调整 Switch 主题色 |
| `lib/features/chat/chat_input.dart` | 移除底栏背景、悬浮样式、模式切换按钮、双模式发送逻辑 |
| `lib/features/home/home_page.dart` | 管理输入模式、调整日历导航栏 padding、移除工具按钮、修改空状态文案、添加固定提示语 |
| `lib/features/home/suggestion_strip.dart` | 减少与输入框的间距 |
| `lib/features/home/side_drawer.dart` | 历史会话列表顶部新增"新建会话" |
| `lib/store/sumi_store.dart` | 启动时自动创建新空会话 |

## Verification Steps

1. 编译通过：`flutter analyze` 无 error。
2. 启动应用后：
   - 首页显示空会话，空状态文案为"Hi, (name)" + 副标题"今天一起做点什么？"。
   - 日历导航栏顶部与灵动岛/状态栏有安全间距。
3. 设置界面：
   - "披露全部月卡"开关颜色正常，不发灰。
   - 苏米记忆区域默认折叠显示摘要，点击编辑后展开。
   - 首页右上角扳手按钮已移除。
4. 输入框：
   - 左侧有圆形模式切换按钮。
   - Sumi 模式：placeholder"尽管说"，可发送消息，可长按语音。
   - Todo 模式：placeholder"添加待办事项"，输入 >16 字后触发 AI 拆分/凝练，<=16 字直接添加。
   - 建议胶囊紧贴输入框。
5. 侧边栏：
   - 顶部有"新建会话"按钮，点击后关闭侧边栏并切换到新会话。
6. 交互：
   - 点击对话空白处仍收起键盘。
   - 月视图展开、滚动到底部按钮仍然可用。

# 首页 UI/UX 优化 V3 开发计划

## Summary

本轮聚焦用户最新反馈的剩余问题：修复设置界面 Switch 颜色与苏米相关设置整合、调整日历导航栏不再顶到灵动岛、重构输入框为真正悬浮的液态玻璃胶囊并优化模式切换细节、让建议胶囊紧贴输入框。模式与文案重新定义：待办模式叫"尽管说"，对话模式叫"尽管问"；空状态文案随模式变化。

## Current State Analysis

### 1. 设置界面（`lib/features/settings/settings_body.dart`）

- 已迁移"苏米记忆"为折叠卡片：默认只读摘要，点击"编辑"展开大文本框，支持保存/清空。
- "披露全部月卡"开关显式设置了 `activeThumbColor` / `activeTrackColor` / `inactiveThumbColor` / `inactiveTrackColor`，但在 Material3 下这些属性可能被主题覆盖或渲染发灰，用户仍觉得颜色不对。
- 缺少"思考模式"开关：该开关原本在 `lib/features/chat/wrench_panel.dart` 中，需要一并移入设置界面，与苏米记忆共同构成"苏米相关设置"。

### 2. 日历导航栏（`lib/features/calendar/date_strip.dart` + `lib/features/home/home_page.dart`）

- `HomePage` 已给 `DateStrip` 增加 `top: MediaQuery.of(context).padding.top + s8`，但用户反馈仍"顶到最上面"，与灵动岛/时间显示冲突。
- `DateStrip` 当前实现：日期格高度 72px、格间距 8px、底部 DragHandle 区域高度 36px，整体视觉偏高；与设计系统 `calendar-nav.json` 中 chipHeight 68px、chipSpacing 4px、dragHandleHeight 6px 不一致。

### 3. 输入框区域（`lib/features/chat/chat_input.dart` + `lib/features/home/suggestion_strip.dart`）

- `ChatInput` 已有模式切换按钮，但胶囊外层仍有整行 Container 兜底，视觉上不是"悬浮"而是"底栏"。
- 发送按钮位于胶囊外部右侧，与设计系统 `chat-input.json` 要求的"send button inside-capsule-right"不符。
- TextField 胶囊的边框/阴影与设计系统仍有差距，用户反馈"有一个很丑的框"。
- `SuggestionStrip` 当前上下 padding 为 `s4`，但与 `ChatInput` 的 `SafeArea` + 顶部 `s8` padding 叠加后，建议区与输入框之间仍有可见间隙。

### 4. 模式切换与文案

- `HomePage` 已管理 `InputMode { chat, todo }`，`ChatInput` 已根据模式切换 placeholder 与图标。
- 待办模式下输入 >16 字时调用 `store.splitAndAddTodo(title)` 触发凝练/拆分的逻辑已存在。
- 当前模式切换按钮 UI 较为简单，需要更细腻的视觉区分（颜色、图标、焦点状态）。
- **文案需重新定义**：
  - 待办模式（todo）→ placeholder："尽管说"
  - 对话模式（chat）→ placeholder："尽管问"
  - （当前代码中 chat 模式 placeholder 为"尽管说"、todo 模式为"添加待办事项"，需对调。）
- **空状态文案需随模式变化**：
  - 待办模式："嗨 [用户名字]，今天要和 sumi 一起做点什么？"
  - 对话模式："嗨，[用户名字]，[随机拉近文案]"（随机从预设池中选取，隐式采集用户信息用于后续建模）
  - （当前空状态固定为"Hi, (name)" + "今天一起做点什么？"，不区分模式，需改为模式联动。）

### 5. 首页打开逻辑与历史会话

- `SumiStore.create()` 中已调用 `createConversation()`，每次启动创建新空会话，显示固定提示语。
- `SideDrawer` 已支持在历史会话列表顶部"新建会话"。
- 以上两点当前实现已符合需求，本轮主要做回归验证。

## Proposed Changes

### 1. 设置界面完善与开关颜色修复

**文件 1: `lib/features/settings/settings_body.dart`**

- **What**: 新增"思考模式"开关区域；修复所有 Switch 颜色发灰问题。
- **How**:
  - 在"苏米记忆"与"开发者"之间新增"思考模式"卡片/区域：
    - 标题："深度思考"
    - 副文案："开启后 Sumi 会在回复前展示推理过程"（或保持简短）
    - 右侧 Switch 绑定 `store.thinkingEnabled` / `store.setThinkingEnabled(v)`
  - 对所有 Switch（披露全部月卡、深度思考）统一封装为私有 `_buildSwitch` 方法，使用 `SwitchTheme` 或显式 `trackColor` / `thumbColor` 的 `WidgetStateProperty` 来确保 Material3 下颜色生效：
    - 开启：`trackColor = primary500`，`thumbColor = Colors.white`
    - 关闭：`trackColor = neutral300`，`thumbColor = Colors.white`
    - 禁用：`trackColor = neutral200`，`thumbColor = neutral200`
  - 移除 `Switch` 上已弃用的 `activeColor` / `activeTrackColor` / `inactiveThumbColor` / `inactiveTrackColor` 写法，避免与 Material3 主题冲突。
- **Why**: 把扳手菜单中剩余的"思考模式"迁入真正的全屏设置；解决用户感知的开关发灰问题。

**文件 2: `lib/theme/app_theme.dart`**

- **What**: 调整 `switchTheme` 使其在 Material3 下输出纯正 primary500 轨道色。
- **How**:
  - 将 `trackColor` 的 selected 分支从任何带 alpha 的颜色改为纯 `primary500`。
  - 确认 `thumbColor` 为白色；disabled 时保持 `neutral200`。
  - 保持 `trackOutlineColor` 透明，维持 iOS 风格。
- **Why**: 从主题根上避免开关显灰，同时作为未显式设置 Switch 的兜底。

**文件 3: `lib/features/chat/chat_page.dart` + `lib/features/chat/wrench_panel.dart`**

- **What**: 删除已不被主流程使用的 `ChatPage` 与 `SumiToolsSheet`（扳手面板）。
- **How**:
  - 删除 `lib/features/chat/chat_page.dart`。
  - 删除 `lib/features/chat/wrench_panel.dart`。
  - 检查 `lib/main.dart`、`lib/features/home/home_page.dart` 等文件，清理对这两个文件的引用（当前已无直接引用，但需确认）。
- **Why**: 功能已迁移到全屏设置与首页输入模式，旧扳手入口与旧 Chat 页面成为悬空代码，按用户"删干净"的要求清理。

### 2. 日历导航栏顶部避让与尺寸还原

**文件 1: `lib/features/calendar/date_strip.dart`**

- **What**: 按设计系统 `calendar-nav.json` 还原日期格与 DragHandle 尺寸，减少整体高度。
- **How**:
  - 日期格宽度从 54px 改为 48px，高度从 72px 改为 68px。
  - `ListView.separated` 的间距从 `s8`（8px）改为 `s4`（4px）。
  - 底部 DragHandle 容器高度从 36px 改为仅包裹 DragHandle 本身（约 6-12px 触控热区），并保留垂直居中对齐。
  - 保持日期下方有日程时的蓝色小圆点（primary500，4px）。
- **Why**: 降低日历区整体高度，视觉上不再"顶到最上面"。

**文件 2: `lib/features/home/home_page.dart`**

- **What**: 给日历导航栏增加更充裕的顶部安全间距。
- **How**:
  - 将 `DateStrip` 外层 `Padding.top` 从 `topPadding + s8` 改为 `topPadding + s16`（或 `s12`，以实际预览为准）。
  - 保持 `bottom: s8` 不变。
  - 可选：若仍觉顶部压迫，可额外在 `DateStrip` 上方插入一个 `SizedBox(height: s8)` 作为呼吸空间。
- **Why**: 确保 iPhone 灵动岛/状态栏文字不与日期条重叠，同时给用户"往下靠"的视觉感受。

### 3. 输入框重构为悬浮液态玻璃胶囊

**文件: `lib/features/chat/chat_input.dart`**

- **What**: 移除底栏背景，改为悬浮胶囊；发送按钮内嵌；模式切换按钮细化。
- **How**:
  - 删除外层 `Container` 的整行背景与顶部边框，仅保留水平 `s16` padding 和底部安全区域 padding。
  - 将 TextField 胶囊改为真正的"液态玻璃"风格：
    - 背景色 `Colors.white.withValues(alpha: 0.85)`
    - `BackdropFilter.blur(sigmaX: 20, sigmaY: 20)`
    - 边框 `1px solid rgba(255,255,255,0.3)`，聚焦/模式色时微变
    - 阴影使用设计系统 `chat-input.json` 的 `0 2px 16px rgba(0,0,0,0.08), 0 0 1px rgba(0,0,0,0.04)`
  - 发送按钮改为内嵌在胶囊右侧：
    - 直径 32px（与设计系统一致）
    - 背景 `_modeColor`
    - 图标白色
    - 空输入时隐藏，有文字时以 AnimatedOpacity/AnimatedScale 渐入
  - 模式切换按钮保留在胶囊左侧：
    - 直径 32px，圆形
    - Sumi 模式：mint/primary 系浅色背景 + mintDeep 图标
    - Todo 模式：accent 系浅色背景 + accent500 图标
    - 增加 Tooltip 或长按提示"切换模式"
  - 录音状态提示条保持位于胶囊上方，但不再扩展整行背景。
  - 待办模式下禁用长按语音（已有逻辑，需确认保留）。
- **Why**: 完全对齐设计系统，解决用户反馈的"背景、丑框、发送按钮缺失"问题。

### 4. 建议胶囊紧贴输入框

**文件 1: `lib/features/home/suggestion_strip.dart`**

- **What**: 减少建议区底部 padding，使其与输入框顶部几乎贴合。
- **How**:
  - 将 `Padding` 改为 `EdgeInsets.only(left: s16, right: s16, top: s4, bottom: s2)`（底部从 `s4` 减到 `s2`）。
  - 若建议内容为空时返回 `SizedBox.shrink()`，避免占用空间。
- **Why**: 消除建议区与输入框之间的视觉间隙。

**文件 2: `lib/features/home/home_page.dart`**

- **What**: 调整输入框区域顶部 padding。
- **How**:
  - 将 `ChatInput` 外层 `SafeArea` 保持，但将 `ChatInput` 内部顶部 padding 从 `s8` 减到 `s4`。
  - 确保 `SuggestionStrip` 与 `ChatInput` 之间无额外 `SizedBox` 或 `Spacer`。
- **Why**: 与建议区一起实现"直接靠到输入框"。

### 5. 模式切换视觉与文案细化

**文件 1: `lib/features/chat/chat_input.dart`**（同第 3 点）

- **What**: 让 Sumi/Todo 两种模式在输入框上有更细腻的视觉区分；placeholder 按新模式定义。
- **How**:
  - 胶囊边框色随模式变化：Chat 模式使用 `mintDeep.withValues(alpha: 0.25)`，Todo 模式使用 `accent500.withValues(alpha: 0.25)`。
  - 胶囊阴影色也随模式变化：Chat 用 mintDeep，Todo 用 accent500。
  - placeholder：**Chat 模式（对话）→ "尽管问"**；**Todo 模式（待办）→ "尽管说"**。
  - 模式切换按钮图标：Chat 用 `chat_bubble_outline`，Todo 用 `task_alt`。
  - 发送按钮图标：Chat 用 `send`，Todo 用 `add_task`。
- **Why**: 用户明确两种模式"会在界面上有所区分，会有一些比较细腻的小细节变化"；且重新定义了模式与文案的对应关系。

**文件 2: `lib/features/home/home_page.dart`**

- **What**: 空状态文案随当前输入模式动态变化。
- **How**:
  - 修改 `_buildEmptyState` 方法，接收 `InputMode mode` 参数：
    - **Todo 模式（"尽管说"）**：
      - 主文案："嗨 [用户名字]，今天要和 sumi 一起做点什么？"
      - 用户名为空时："嗨，今天要和 sumi 一起做点什么？"
    - **Chat 模式（"尽管问"）**：
      - 主文案："嗨，[用户名字]，[随机文案]"
      - 用户名为空时："嗨，[随机文案]"
      - 随机文案从预设池中 `Random` 选取，每次进入空状态时刷新一次。
  - 预设随机文案池（Chat 模式用，隐式采集用户信息、拉近距离）：
    ```dart
    const _chatGreetings = [
      '最近在忙什么有趣的事？',
      '有什么好奇想问的吗？',
      '今天学了什么新东西？',
      '最近有什么想聊的话题？',
      '今天过得怎么样？',
      '有什么我可以帮你的吗？',
      '最近在读什么书或者看什么课？',
      '有什么想尝试但还没开始的事吗？',
    ];
    ```
  - 在 `_HomePageState` 中维护 `String _chatGreeting` 字段，切换到 Chat 空状态时随机选一条；切换模式时刷新。
- **Why**: 用户要求空状态文案与模式联动，Chat 模式下用随机文案拉近距离并为后续用户建模做话匣子。

### 6. 首页打开逻辑与历史新建（回归验证）

**文件: `lib/store/sumi_store.dart` + `lib/features/home/side_drawer.dart`**

- **What**: 确认现有逻辑无需改动，只做验证清单。
- **How**:
  - `SumiStore.create()` 中 `loadConversations()` 后调用 `createConversation()` 保持不变。
  - `SideDrawer` 顶部"新建会话"入口保持不变。
- **Why**: 这两点已在前序轮次实现，本轮纳入回归验证即可。

## Assumptions & Decisions

1. **"苏米设置里的开关"指思考模式开关**：将其从扳手面板迁移到全屏设置，与苏米记忆同属"Sumi 相关设置"。
2. **Switch 颜色修复方式**：不再使用 Material2 的 `activeColor` / `activeTrackColor`，统一使用 `WidgetStateProperty` 或直接覆盖 `SwitchTheme`，确保 Material3 生效。
3. **日历导航栏"往下靠"**：通过增加顶部安全 padding 与缩减组件自身高度共同实现，不引入新的 AppBar。
4. **输入框"无背景"**：指去除整行底栏背景，改为悬浮胶囊；胶囊本身保留半透明液态玻璃背景，以符合设计系统。
5. **发送按钮位置**：按设计系统内嵌于胶囊右侧，而非独立在胶囊外。
6. **ChatPage 与 wrench_panel 可删除**：主流程使用 `HomePage`，旧 Chat 页与扳手面板已没有独立入口，删除不会造成功能丢失。
7. **模式与文案对应关系**：Todo 模式（待办输入）placeholder 为"尽管说"；Chat 模式（Sumi 对话）placeholder 为"尽管问"。空状态文案随模式变化：Todo 模式显示"嗨 [用户名字]，今天要和 sumi 一起做点什么？"；Chat 模式显示"嗨，[用户名字]，[随机拉近文案]"。

## Files to Modify

| 文件 | 主要改动 |
|------|----------|
| `lib/features/settings/settings_body.dart` | 新增"深度思考"开关；修复 Switch 颜色；苏米记忆保持折叠卡片 |
| `lib/theme/app_theme.dart` | 校正 SwitchTheme 轨道色为纯 primary500 |
| `lib/features/chat/wrench_panel.dart` | 删除 |
| `lib/features/chat/chat_page.dart` | 删除 |
| `lib/features/calendar/date_strip.dart` | 还原设计系统尺寸：48×68 日期格、4px 间距、精简 DragHandle 高度 |
| `lib/features/home/home_page.dart` | 增加日历顶部 padding；调整 ChatInput 顶部 padding；空状态文案随模式变化（含随机文案池） |
| `lib/features/chat/chat_input.dart` | 移除底栏背景；液态玻璃悬浮胶囊；内嵌发送按钮；placeholder 按新模式（chat→"尽管问"，todo→"尽管说"） |
| `lib/features/home/suggestion_strip.dart` | 减少底部 padding 以紧贴输入框 |

## Verification Steps

1. 编译与静态检查：
   - `flutter analyze` 无 error，无新增 warning。
   - 确认 `wrench_panel.dart`、`chat_page.dart` 已删除且无引用残留。

2. 设置界面：
   - 进入设置后，"深度思考"开关可见且可正常切换。
   - "披露全部月卡"与"深度思考"两个开关开启时均为纯 primary500 轨道 + 白色 thumb，关闭时为 neutral300 轨道，不发灰。
   - "苏米记忆"默认折叠显示摘要，点击"编辑"展开大输入框，保存/清空功能正常。

3. 日历导航栏：
   - 首页顶部日期条与灵动岛/状态栏有清晰间距，不重叠。
   - 日期格高度、间距、DragHandle 高度符合设计系统，整体视觉不再"顶到最上面"。
   - 有日程的日期下方仍显示蓝色小圆点。

4. 输入框：
   - 无整行底栏背景，胶囊悬浮在内容上方。
   - 左侧圆形按钮可切换 Chat/Todo 模式；模式变化时胶囊边框色、阴影色、placeholder、发送图标均有细腻变化。
   - **Chat 模式 placeholder 为"尽管问"**，可打字发送，可长按语音。
   - **Todo 模式 placeholder 为"尽管说"**，输入 >16 字触发 `splitAndAddTodo` 凝练/拆分，≤16 字直接添加。
   - 有文字时胶囊右侧出现内嵌发送按钮，空输入时隐藏。

5. 建议胶囊：
   - 建议区与输入框顶部之间无可见间隙，视觉上"直接靠到输入框"。
   - 点击建议可正常发送。

6. 首页打开与历史：
   - 冷启动后首页为空会话，空状态文案根据默认模式（Chat）显示"嗨，[用户名字]，[随机拉近文案]"。
   - 切换到 Todo 模式后空状态变为"嗨 [用户名字]，今天要和 sumi 一起做点什么？"。
   - 左侧划出历史会话，顶部"新建会话"可创建新会话并关闭侧边栏。

7. 交互回归：
   - 点击对话空白处仍可收起键盘。
   - 日历底部 DragHandle 可展开月视图。
   - 侧边栏左右滑入滑出动效正常。
   - 设置界面从右侧全屏滑入，左上角返回按钮可返回。

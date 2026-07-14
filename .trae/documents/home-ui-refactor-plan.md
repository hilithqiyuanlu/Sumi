# Sumi 首页 UI/UX 重构计划

## Summary

将当前基于底部 3 Tab（Sumi / 事项 / 设置）的导航结构，重构为单一首页。首页自上而下包含：日历导航栏、横向滚动胶囊待办区、对话区、建议区、底部输入区。左侧通过横向拖拽呼出占屏 5/6 的侧边栏（用户名片 + 历史会话 + 设置入口），点击设置后从右侧滑入占屏 5/6 的设置界面。所有呼出过程需带 UI 动效。

## Current State Analysis

- **入口与导航**：`lib/main.dart` 的 `home` 指向 `MainShell`（`lib/main_shell.dart`），`MainShell` 通过 `IndexedStack` + 底部自定义导航实现 3 Tab 切换。
- **聊天模块**：`lib/features/chat/chat_page.dart` 为独立页面，使用 `Scaffold` + `AppBar`，消息列表为 `ListView`，空状态为居中图标+文字。`ChatBubble` 支持用户/AI 两种样式、思考过程、工具调用提示。`ChatInput` 已包含文本输入、语音长按、发送按钮，placeholder 已经是"尽管说"。
- **待办模块**：`lib/features/todos/todos_page.dart` 为独立页面，包含 `DateStrip`、`TodoGrid`（瀑布流卡片）、`TodoInput`。`TodoCard` 展示完成状态、置顶、项目归属、提醒时间等完整功能。
- **日历组件**：`lib/features/calendar/date_strip.dart` 为折叠态日期条，当前实现为整月日期横向滚动，选中日期为靛蓝背景，但无"有事项天数字下小蓝点"标记，拖拽把手区域在日期条下方。
- **会话列表**：`lib/features/chat/conversation_list.dart` 以底部 Sheet 形式展示历史会话，支持点击切换、长按删除。
- **设置页**：`lib/features/settings/settings_page.dart` 为普通页面，通过 Tab 切换进入。
- **状态管理**：`SumiStore`（`lib/store/sumi_store.dart`）为单一 `ChangeNotifier`，通过 `SumiScope` 注入。`AppSettings` 目前无用户名字段。`SumiStoreChat` 已支持会话 CRUD，但无置顶/重命名方法。`AiService` 无建议问题生成方法。
- **主题与 Token**：`lib/theme/app_theme.dart` 已定义颜色、间距、圆角等设计 Token，可直接复用。

## Proposed Changes

### Phase A：数据层与状态层扩展

1. **`lib/models/models.dart`**
   - 在 `AppSettings` 中新增 `userName` 字段（默认空字符串），并同步更新 `copyWith`、`toJson`、`fromJson`。
   - **Why**：支持用户名片可编辑昵称的持久化。

2. **`lib/store/sumi_store.dart`**
   - 新增 `updateUserName(String name)` 方法，调用 `afterMutation()` 持久化。
   - **Why**：提供修改用户昵称的入口。

3. **`lib/store/sumi_store_chat.dart`**
   - 新增 `pinConversation(String id, {bool pinned = true})`：置顶/取消置顶会话（仅内存排序，置顶项移到队首，取消置顶后按更新时间重新插入）。
   - 新增 `renameConversation(String id, String newTitle)`：更新 DB 与会话列表中的标题。
   - **Why**：满足侧边栏历史会话"长按呼出 tips 可置顶/rename/删除"需求。

4. **`lib/services/ai_service.dart`**
   - 新增 `_suggestionsSystemPrompt` 提示词：要求基于今日待办和记忆生成 3-5 个自然简洁的建议问题，输出 JSON。
   - 新增 `generateSuggestions({required String todayTodosText, required String memory})` 非流式 JSON 方法。
   - **Why**：支持建议区 AI 建议提问内容的轮询更新。

### Phase B：首页主体重构

5. **删除旧 Tab 壳（`lib/main_shell.dart`）**
   - 直接删除该文件；`lib/main.dart` 的 `home` 改为新的 `HomePage`。
   - **Why**：用户明确要求"删除 tab"，底部导航不再需要。

6. **新建 `lib/features/home/home_page.dart`**
   - 作为新的首页，使用 `Scaffold` 但不使用 `AppBar`。
   - 整体结构：
     ```
     Stack(
       children: [
         // 1. 主内容列
         Column(
           children: [
             DateStrip(...),              // 日历导航
             TodoChipCarousel(...),       // 横向胶囊待办
             Expanded(child: ChatArea()), // 对话区（空状态/消息列表）
             SuggestionStrip(...),        // 建议区
             ChatInput(...),              // 底部输入
           ],
         ),
         // 2. 侧边栏（左侧滑入，占屏 5/6）
         SideDrawer(...),
         // 3. 设置页（右侧滑入，占屏 5/6）
         SettingsPanel(...),
       ],
     )
     ```
   - 管理状态：`bool _drawerOpen`、`bool _settingsOpen`、手势拖拽位移。
   - 手势逻辑：
     - 在首页左侧边缘横向右滑（`DragStartBehavior.down` + 起始 x < 20）打开侧边栏。
     - 侧边栏打开时，从左边缘向左滑或点击遮罩关闭。
     - 设置页打开时，从右边缘向右滑或点击遮罩关闭。
   - **Why**：将所有功能聚合到单一首页，实现用户要求的动效呼出。

7. **修改 `lib/features/calendar/date_strip.dart`**
   - 保留日期条横向滚动与选中逻辑。
   - 新增：对每个日期，根据 `store.todoItems` 中 `date == dateKey(date)` 且未完成的数量判断是否有事项，有则在数字下方显示 4px 小蓝点（`primary500`）。
   - 调整：将拖拽把手/展开月视图的横线区域从当前居中改为整体靠下（容器 alignment 从 `Alignment(0, 0.4)` 改为更靠下，如 `Alignment(0, 0.75)`），并降低高度（如 36px）。
   - **Why**：满足"有事项的天数字下有小圆蓝点；下方的横线在靠下些"。

8. **新建 `lib/features/todos/todo_chip_carousel.dart`**
   - 组件展示选中日期相关的待办（`date == null || date == dateKey(selectedDate)`）。
   - 布局方式：使用 `SingleChildScrollView(scrollDirection: Axis.horizontal)` 包裹 `Wrap`，实现多行流式横向滚动。最多支持 3 行，超出部分可横向滚动。
   - 胶囊宽度计算：根据标题字数动态决定，公式为 `minPadding + titleLength * charWidth + maxPadding`，其中 `charWidth` 约为 16px（基于 14px 字号），最小宽度 80px，最大宽度 200px。
   - 排序规则：未完成的待办排在前面（按创建时间/优先级），已完成的待办排在后面。
   - 每个待办渲染为胶囊：圆角 `radiusPill`，背景 `surfaceChip`，左侧可点击圆形完成图标（根据 `done` 显示 `check_circle` / `circle_outlined`），右侧标题文本。已完成胶囊背景变灰（`neutral200`），文字变浅（`textTertiary`）。
   - 自动滚动：通过 `AnimationController` + `ScrollController.animateTo` 实现慢速横向滚动。为支持循环，将待办列表复制一份拼接，当滚动超过原始列表总宽度时无缝跳回起点。
   - 手动滚动：保持 `BouncingScrollPhysics`，用户拖拽时暂停自动滚动，松开后恢复。
   - 长按菜单：弹出 `PopupMenuButton` 或自定义菜单，提供"置顶"、"编辑"、"删除"选项。
   - **Why**：实现用户要求的"一行满了，再在下一行列"的多行循环逻辑，且"已经完成了的任务，默认顺序就到后面的"。
   - **Note**：用户要求"具体 todo 项完全删除定时逻辑和功能"，因此胶囊只展示标题和完成状态，不显示提醒时间、项目归属等扩展信息。

9. **修改 `lib/features/chat/chat_bubble.dart`**
   - 保留用户/AI 气泡基础样式，但去除顶部的"你 / Sumi"角色标签（首页对话区更简洁）。
   - 新增时间坐标：在每条用户消息上方居中显示发送时间，格式 `MM/DD HH:mm`。
   - **Why**：满足"对话信息从用户输入时间算起居中标一个小时间坐标"。

10. **在 `lib/features/home/home_page.dart` 内联实现 `ChatArea`**
    - 空状态：`messages.isEmpty` 时显示 `"嗨 ${userName.isEmpty ? '' : ' $userName'}，今天要和 Sumi 一起做点什么"`，居中显示。
    - 有对话时：使用 `ListView.builder` 展示消息，顶部与待办区保持固定间距（如 `s16`）。
    - 消息列表区域与空状态区域在视觉上占据相同垂直权重（通过 `Expanded` 包裹）。
    - **Why**：满足对话区空状态与间距要求。

11. **新建 `lib/features/home/suggestion_strip.dart`**
    - 横向滚动的建议问题胶囊列表，使用 `ListView` 或 `SingleChildScrollView`。
    - 胶囊样式：白色/浅灰背景、靛蓝文字、圆角 pill、内边距适中。
    - 点击某条建议：自动填入输入框或直接调用 `store.sendMessage(text)`。
    - 数据来源：由 `HomePage` 通过 `Timer.periodic(Duration(seconds: 30), ...)` 调用 `AiService.generateSuggestions` 维护本地 `List<String> suggestions`。
    - 首次进入首页即触发一次生成；当 API 不可用时显示 3 条本地兜底建议。
    - **Why**：满足"建议区：ai建议提问内容，轮询定时更新"，且用户补充"建议区也是可以左右滑动"。

12. **修改/复用 `lib/features/chat/chat_input.dart`**
    - 当前 placeholder 已经是"尽管说"，保持即可。
    - 用户要求"图片里的添加先不做"：当前输入栏没有图片按钮，无需额外修改。
    - 适配首页底部使用：保持现有的语音长按、发送按钮逻辑。
    - **Why**：满足输入区文案与简化要求。

### Phase C：侧边栏与设置动效

13. **新建 `lib/features/home/side_drawer.dart`**
    - 占屏宽度 5/6 的侧边抽屉，通过 `AnimatedPositioned` 或 `SlideTransition` 从左侧滑入。
    - 内容：
      - 顶部安全区 + 用户名片（点击可编辑名字，弹出 `TextField` Dialog 或切换为编辑态）。
      - 历史会话列表（`ListView`），项之间显示分隔线；当前会话高亮。
      - 左下角设置按钮（图标 `Icons.settings`），点击关闭侧边栏并打开设置面板。
    - 交互：
      - 会话项长按弹出菜单：置顶 / 重命名 / 删除。
      - 重命名使用 `TextField` Dialog。
      - 删除二次确认 Dialog。
    - **Why**：满足侧边栏所有功能与动效要求。

14. **新建 `lib/features/home/settings_panel.dart`**
    - 占屏宽度 5/6 的右侧面板，通过 `AnimatedPositioned` 或 `SlideTransition` 从右侧滑入。
    - 内容复用 `SettingsPage` 的核心 UI（API Key 管理、开发者开关、清除数据、版本号），但不再使用 `Scaffold`/`AppBar`，改为面板标题栏 + 关闭按钮。
    - 关闭方式：点击关闭按钮、点击左侧露出的 1/6 区域、从右边缘向右滑。
    - **Why**：满足"设置（左下角）按钮（点击从右向左呼出设置界面）"与动效要求。

15. **`lib/features/settings/settings_page.dart` 处理**
    - 如果 `SettingsPanel` 完全内联实现，则该文件可保留但不再从 Tab 进入；或提取公共组件 `SettingsBody` 供两者复用。
    - **建议**：保留 `SettingsPage` 文件，新增 `SettingsBody` StatelessWidget 在 `lib/features/settings/settings_body.dart`，`SettingsPage` 与 `SettingsPanel` 均引用它。
    - **Why**：避免代码重复，同时保留独立页面以备未来使用。

### Phase D：收尾与验证

16. **`lib/main.dart`**
    - 将 `home: const MainShell()` 改为 `home: const HomePage()`。
    - 删除 `MainShell` 的 import。
    - **Why**：完成入口迁移。

17. **依赖检查**
    - 确认无需新增第三方依赖。所有动效使用 Flutter 内置 `AnimatedPositioned`、`SlideTransition`、`GestureDetector` 即可。
    - **Why**：降低引入风险。

## Assumptions & Decisions

| 决策点 | 方案 | 理由 |
|--------|------|------|
| 用户名片昵称持久化 | 存到 `AppSettings.userName` | 与现有设置持久化机制一致，无需新增表 |
| 待办胶囊交互 | 点击切换完成，长按弹出置顶/编辑/删除菜单 | 用户明确选择"支持完成+长按菜单" |
| 待办自动滚动速度 | 约 30-40 px/秒 | 类似弹幕但不过快；可在实现时微调 |
| 建议区轮询间隔 | 30 秒 | 平衡实时性与 API 调用成本；可在实现时微调 |
| 建议区兜底内容 | API 不可用时展示 3 条预置建议 | 避免空白 |
| 设置面板宽度 | 占屏 5/6，从右侧滑入 | 用户原话"点击从右向左呼出"，且选择"占屏 5/6" |
| 侧边栏宽度 | 占屏 5/6，从左侧滑入 | 用户明确要求 |
| 月视图展开 | 保留原 `DateStrip` 的横线点击展开逻辑 | 用户未要求删除 |
| 语音输入 | 保留 `ChatInput` 现有长按语音逻辑 | 用户未要求改动 |
| 项目/规划入口 | 暂时只通过展开的月视图进入 | 删除 Tab 后项目入口保留在月视图 |

## Verification Steps

1. 编译通过：`flutter analyze` 无 error。
2. 运行应用后：
   - 底部无 Tab 栏，直接显示首页。
   - 日历条有事项的日期下方出现小蓝点；横线位置靠下。
   - 待办区显示为一行胶囊，自动慢速循环滚动，可手动左右滑动；点击切换完成状态，长按出现菜单。
   - 无对话时显示问候语（含用户名/空）；有对话时显示消息，用户消息上方居中显示时间。
   - 建议区横向滚动，每 30 秒自动更新建议问题，点击可发送。
   - 输入框 placeholder 为"尽管说"，无图片按钮。
   - 从屏幕左边缘右滑呼出侧边栏（占 5/6），显示用户名片、历史会话、左下角设置按钮。
   - 历史会话长按可置顶、重命名、删除。
   - 点击设置按钮后设置面板从右侧滑入（占 5/6），可关闭。
3. 持久化验证：修改用户名后杀进程重开，用户名保留。
4. 会话操作验证：置顶、重命名、删除后，侧边栏列表实时更新。

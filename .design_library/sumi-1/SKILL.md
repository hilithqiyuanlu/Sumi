# Sumi Design System v2 -- AI 消费规则（从真实项目反向提取）

当 AI 助手使用此设计系统生成 UI 或代码时，必须遵循以下规则。所有 Token 值均从 Sumi App Flutter 项目源码提取。设计系统只包含项目实际使用的 Token 和组件，不引用未定义的组件或 Token。

## Token 引用规则

### 颜色
- 品牌主色：使用 `var(--primary)` = `#4758E0`（Indigo Blue，@primary 标注在 500），不要直接写 hex
- primary-600 深色：使用 `var(--primary-600)` = `#3740C7`（Suggestion Chip 文字等）
- 用户气泡背景：使用 `var(--chat-user-bg)` = `var(--primary-100)`（淡 Indigo），不是深蓝
- AI 气泡背景：使用 `var(--chat-ai-bg)` = `var(--surface-container)`
- 背景色：`var(--color-background)` 或 `var(--color-surface)` 或 `var(--color-paper)` = `#FFFFFF`
- 文字色：主要用 `var(--on-surface)` = `var(--neutral-900)` = `#0E1115`, 辅助用 `var(--on-surface-variant)` = `var(--neutral-500)`, 三级文字用 `var(--color-text-tertiary)` = `#7F8D9F`
- Icon 色：默认 `var(--icon-default)` = `#0E1115`, 品牌色 `var(--icon-brand)` = `#4758E0`
- Border：`var(--border-l1)` = `rgba(14,17,21,...)` 或 `var(--color-line)` = `#EBEBEB`
- Chip 背景：`var(--color-surface-chip)` = `#EFF1F4`
- mint / mintDeep：`var(--color-mint)` = primary-100, `var(--color-mint-deep)` = `#4758E0`
- 状态色：success `#42B570`, warning `#F1BA30`, error `#D95D4F`, info `#5292D4`（使用 `--success-default`, `--warning-default`, `--error-default`, `--info-default`）
- Project Colors: lemon, mint, lilac, cherry, sky, peach, sage（7 种项目标记色）

### 排版（8 级 + 1 特殊）
- 卡片标题：`.sumi-h3` 或 `var(--font-size-h3)` (24px, w800)
- 子标题：`.sumi-h4` 或 `var(--font-size-h4)` (20px, w800)
- 中号标题：`.sumi-h-md` 或 `var(--font-size-h-md)` (18px, w600)
- 小号标题：`.sumi-h-sm` 或 `var(--font-size-h-sm)` (16px, w700)
- 角色标签：`.sumi-h-xs` (13px, w600)
- 基础正文：`.sumi-body-base` 或 `var(--font-size-body-base)` (14px, w500)
- 中号正文：`.sumi-body-md` 或 `var(--font-size-body-md)` (15px, w400)
- 小号正文：`.sumi-body-sm` 或 `var(--font-size-body-sm)` (13px, w400)
- 日期显示：`.sumi-display-date` (22px, w700，Calendar Nav 选中态)
- 字体族：统一使用 `PingFang SC`（项目实际使用，无 Inter / JetBrains Mono）

### 间距（12 级）
- 使用 `var(--space-N)` 变量，不要直接写 px
- 常用组合：卡片内 padding `var(--space-6)`, 组件间距 `var(--space-4)`, 页面边距 `var(--space-7)` = 14px
- **注意 `--space-7` = 14px（不是 16px！）**

### 圆角（6 级 + pill）
- Chip：`var(--radius-pill)` (9999px)
- 输入框：`var(--radius-8)` 或 `var(--radius-12)`
- 卡片：`var(--radius-card)` = **18px**（不是 16px！）
- Sheet 顶部：`var(--radius-card-header)` = **20px**
- Calendar Nav chip：`var(--radius-card)` = **18px**（52x72 chip）
- 对话气泡：用户右上小圆角 `var(--radius-20) var(--radius-20) var(--radius-20) 4px`，AI 反过来（左上小圆角）

### 阴影（2 级）
- 卡片：`var(--shadow-1)`（基于 rgba(14,17,21,...)）
- 卡片悬浮：`var(--shadow-2)`

## 组件组合规则

### 对话全屏布局
从上到下依次为：
1. App Bar (固定顶部)
2. Chat 区域（可滚动）
   - Empty State（无消息时）或 Chat Bubble 列表
   - **无角色标签**（气泡上方不显示"你"/"Sumi"等标签）
   - 时间戳格式 M/D HH:MM
3. Suggestion Chip 区域（可选）
4. Chat Input（固定底部，含 safe area）
   - **左侧有模式切换按钮**（44x44）
   - pill 输入框 + 胶囊内发送按钮（44x44）
   - backdrop-filter: blur(24), bg white@82%

### 待办页面布局
1. App Bar（含菜单按钮，点击打开 Side Drawer）
2. Calendar Navigation（52x72 chip，radiusCard=18px，整月横向滚动，selected=mintDeep=#4758E0）
3. Todo Chip 列表
   - pending 态 / completed 态混合
4. Chat Input（底部快速创建，含左侧模式切换按钮）

### Side Drawer 布局
1. Scrim 遮罩层（rgba(14,17,21,0.4)）
2. 左侧抽屉面板（width 280px，radius-card 右侧圆角 18px）
   - 用户信息区（头像 + 用户名）
   - 项目列表（pill 形式，各项目色 @25% 透明度背景）
   - 设置入口卡片（底部）

### Chat Bubble 规则
- 用户气泡：右上小圆角，maxWidth 72%
- AI 气泡：左上小圆角，maxWidth 72%
- **无角色标签**（气泡上方不显示用户/AI 名称）
- 时间戳：M/D HH:MM 格式
- 支持 streaming / reasoning 变体

### Todo Chip 规则
- **pending 态**：左侧空心圆圈（transparent 背景 + 1.5px 边框，点击可完成），padding 10px 14px，15px w500
- **completed 态**：左侧实心圆圈（primary-container 背景 + 白色勾）+ **muted 文字（无 line-through 划线！）**

### Suggestion Chip 规则
- 背景：`var(--color-surface-chip)` = `#EFF1F4`
- 文字色：`var(--primary-600)` = `#3740C7`
- pill 形状（radius-full）

### Bottom Sheet 使用
- 所有 sheet 共享：radius-card-header (20px) 顶部圆角 + DragHandle (36x4px)
- 对话列表：DraggableScrollableSheet, initialChildSize 0.6
- 编辑面板：固定内容，含操作入口行
- 确认面板：标题 + 列表 + 双按钮

### Secondary App Bar（二级页面导航栏）
所有二级页面（可校正理解、本地检索、信号日志、记忆编辑器、模型路由诊断、新建项目等）必须使用统一 AppBar：
- 背景：`paper`（白色），`surfaceTintColor: paper`
- 默认 elevation: 0
- 滚动后 elevation: `scrolledUnderElevation: 2`（出现微妙阴影）
- 标题：16px, w600, ink 色，居左（`centerTitle: false`）
- 返回按钮：`Icons.arrow_back`（系统默认）
- fullscreenDialog 页面（如新建项目）：系统自动显示 close 图标
- 不要自定义 Row/Positioned 模拟 AppBar，统一使用 `AppBar(title:)` 组件
- 不要在每个页面重复指定 backgroundColor/surfaceTintColor/elevation（全局 ThemeData 已配置）

## 移动端适配规则

### 断点
- 当前仅针对移动端（375px ~ 428px 宽度）
- 最大内容宽度：100%（无 max-width 限制）
- 安全区域：底部 Tab Bar 下方 + 顶部状态栏留空

### 触屏交互
- 不依赖 hover 态（iOS 无 hover）
- 交互区域最小 44x44px
- 按/松反馈：brightness(0.97) 或 iOS highlight
- 长按手势：触发上下文菜单或语音输入

### 手势
- 拖拽排序：长按 200ms 进入拖拽，原位 0.3 透明度占位
- 左滑删除：显示 danger 背景 + 删除图标
- 下拉展开：Calendar Nav 下拉展开月视图

## 禁止事项

1. 不要硬编码颜色值，必须使用 CSS 变量
2. 不要使用 hover 作为唯一交互态（iOS 不支持）
3. 不要引用不存在的组件（Button、Input、Toggle、Avatar、Badge、Dialog、Toast、Divider、Send Button、Voice Hint Bar、Action Chip、Collapsible Section、Todo Card 均已移除）
4. 不要使用不存在的排版阶梯（display、display-sm、h1、h2、h-lg、h-2xs、h-3xs、body-lg、body-base-strong、body-xs）
5. 不要使用 Inter 或 JetBrains Mono 字体（项目只使用 PingFang SC）
6. 不要使用 shadow-3/4/5（项目只使用 shadow-1 和 shadow-2）
7. 不要在对话气泡中使用深色背景（用户气泡是淡色 primary-100）
8. **不要在对话气泡上方显示角色标签**（真实项目无此设计）
9. **不要给 Todo Chip completed 态添加 line-through**（项目只使用 muted 文字）
10. **不要使用 `--primary` = `#4b3fe3`**（那是旧值，正确值为 `#4758E0`）
11. **不要使用 `--radius-card` = 16px**（正确值为 18px）
12. **不要使用 `--space-7` = 16px**（正确值为 14px）
13. 不要在非 primary 场景使用高饱和度色彩（accent 色阶均为低饱和度版本）
14. 不要混用 rem 和 px（CSS 变量用 px，排版类用 rem）
15. 不要修改 `--accent-*`、`--tertiary-*` legacy 别名（保持向后兼容）

## 代码生成指引

### Flutter/Dart
- Token 对应 lib/theme/app_theme.dart 中的主题配置
- 颜色引用：Theme.of(context).extension<SumiTheme>().primary
- 字体引用：Theme.of(context).textTheme.bodyBase

### CSS/HTML
- 引用方式：`<link rel="stylesheet" href="colors_and_type.css">`
- 使用 `.sumi-*` 排版类或直接引用 `var(--xxx)` 变量
- 预览页面必须使用外部 CSS 链接，不内联 token

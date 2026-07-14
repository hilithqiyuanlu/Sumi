# Sumi Design System v2 — AI 消费规则（基于 TRAE Work Token）

当 AI 助手使用此设计系统生成 UI 或代码时，必须遵循以下规则。

## Token 引用规则

### 颜色
- 品牌主色：使用 `var(--primary)` = `#4b3fe3`（TRAE Work brand-600），不要直接写 hex
- Hover 态：使用 `var(--color-primary-hover)` = `#6a6fff`
- Soft 态：使用 `var(--color-primary-soft)` = `rgba(170,183,255,0.36)`
- 用户气泡背景：使用 `var(--chat-user-bg)` = `var(--primary-100)` = `#e5eaff`（淡紫蓝），不是深蓝
- AI 气泡背景：使用 `var(--chat-ai-bg)` = `var(--surface-container)`
- 背景色：`var(--color-background)` 或 `var(--color-surface)`
- 文字色：主要用 `var(--on-surface)` = `var(--neutral-900)` = `#171717`, 辅助用 `var(--on-surface-variant)` = `var(--neutral-500)` = `#737373`
- Icon 色：默认 `var(--icon-default)` = `#262626`, 品牌色 `var(--icon-brand)` = `#4b3fe3`
- Border：`var(--border-l1)` = `rgba(115,115,115,0.12)`
- Tag/Chip 多彩背景：使用 `var(--tag-indigo)`, `var(--tag-violet)`, `var(--tag-teal)` 等（均为低饱和度色调）
- 状态色（TRAE Work 体系）：success/warning/error/info/alert 使用 `--success-default`, `--warning-default`, `--error-default`, `--info-default`, `--alert-default`（均含 surface 变体）

### 排版
- 页面标题：`.sumi-h1` 或 `var(--font-size-h1)` + `var(--font-weight-h1)`
- 卡片标题：`.sumi-h3` 或 `var(--font-size-h3)`
- 正文：`.sumi-body` 或 `var(--font-size-body-base)`
- 小字/标签：`.sumi-h-2xs` (12px) 或 `.sumi-body-sm` (11px)
- 角色标签：`.sumi-h-xs` (13px, w600)
- 代码：`.sumi-code-editor` (13px) 或 `.sumi-mono`
- 字体族：body 用 `var(--font-body)`, heading 用 `var(--font-heading)`, mono 用 `var(--font-mono)`

### 间距
- 使用 `var(--space-N)` 变量，不要直接写 px
- 常用组合：卡片内 padding `var(--space-6)`, 组件间距 `var(--space-4)`, 页面边距 `var(--space-7)`

### 圆角
- 按钮/Chip：`var(--radius-full)` (9999px)
- 日期 Chip：`var(--radius-10)`
- 输入框：`var(--radius-12)`
- 卡片：`var(--radius-card)` = `var(--radius-16)` = 16px
- Sheet 顶部：`var(--radius-card-header)` = `var(--radius-20)` = 20px
- 对话气泡：用户 `var(--radius-20) var(--radius-20) var(--radius-20) 4px`，AI 反过来

### 阴影
- 卡片：`var(--shadow-1)`
- 悬浮/弹窗：`var(--shadow-4)` 或 `var(--shadow-5)`
- 拖拽中卡片：`var(--shadow-4)`

## 组件组合规则

### 对话全屏布局
从上到下依次为：
1. App Bar (固定顶部)
2. Chat 区域（可滚动）
   - Empty State（无消息时）或 Chat Bubble 列表
   - 气泡上方有角色标签
   - 用户气泡上方居中显示时间戳
3. Suggestion Chip 区域（可选）
4. Voice Hint Bar（录音时显示，可选）
5. Chat Input + Send Button（固定底部，含 safe area）
   - 左侧无图标按钮，pill 输入框 + 右侧发送按钮

### 待办页面布局
1. App Bar
2. Calendar Navigation（圆角矩形日期 chip，radius-10，整月横向滚动，可下拉展开月视图）
3. Todo Card 瀑布流 (MasonryGridView)
   - default/project-colored/with-reminder 变体混合
4. Chat Input（底部快速创建，无左侧图标，纯文字输入）

### Todo Chip 规则
- **pending 态**：左侧 18px 空心圆圈（transparent 背景 + 1.5px on-surface-variant 边框，点击可完成）
- **completed 态**：左侧实心圆圈（primary-container 背景 + 白色勾）+ 文字划线 + muted 色调

### Bottom Sheet 使用
- 所有 sheet 共享：radius-card-header (20px) 顶部圆角 + DragHandle (36x4px)
- 对话列表：DraggableScrollableSheet, initialChildSize 0.6
- 编辑面板：固定内容，含 ActionChip 行
- 确认面板：标题 + 列表 + 双按钮

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
3. 不要在移动端使用大于 h1 的标题（display 仅用于数据大屏）
4. 不要混用 rem 和 px（CSS 变量用 px，排版类用 rem）
5. 不要修改 --accent-*, --tertiary-* legacy 别名（保持向后兼容）
6. 不要在对话气泡中使用深色背景（用户气泡是淡色 primary-100）
7. 不要在 Chat Input 左侧放图标按钮（实际无加号按钮）
8. 不要使用 `--radius-pill`（已移除，统一用 `--radius-full`）
9. 不要使用旧的 `--primary-500` 作为主色（主色是 `--primary` = `--primary-600` = `#4b3fe3`）
10. 不要在非 primary 场景使用高饱和度色彩（accent 色阶均为低饱和度版本，仅 `--primary` 系列保持高饱和度）

## 代码生成指引

### Flutter/Dart
- Token 对应 lib/theme/app_theme.dart 中的主题配置
- 颜色引用：Theme.of(context).extension<SumiTheme>().primary
- 字体引用：Theme.of(context).textTheme.bodyBase

### CSS/HTML
- 引用方式：`<link rel="stylesheet" href="colors_and_type.css">`
- 使用 `.sumi-*` 排版类或直接引用 `var(--xxx)` 变量
- 预览页面必须使用外部 CSS 链接，不内联 token

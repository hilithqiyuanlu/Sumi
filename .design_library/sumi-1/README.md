# Sumi Design System v2 — 基于 TRAE Work Token 体系的移动端设计系统

面向移动端 App 的设计系统，Token 体系全面对齐 TRAE Work，品牌色采用 TRAE Work 紫蓝 (#4b3fe3)，SF Pro / PingFang SC 字体体系、iOS 原生设计语言。

## 设计理念

- **简洁克制**：白色基底 + TRAE Work 紫蓝点缀，信息密度适中；**非 primary 色彩均使用低饱和度色调**，避免鲜亮高饱和色干扰
- **温暖陪伴**：圆润的 `radius-card` (16px) 和 pill 形状传递友好感
- **智能辅助**：AI 对话是核心交互，组件围绕对话 + 任务展开
- **物理反馈**：弹簧动画、触觉反馈、拖拽手势提供自然交互感
- **TRAE Work 对齐**：色彩色阶、字体、间距、圆角、阴影全面与 TRAE Work 一致；项目色（accent-coral/amber/teal/cyan/violet）和 tag 色板采用低饱和度版本

## Token 体系

### 色彩

- **Primary (TRAE Work 紫蓝)**: `#4b3fe3` — 品牌主色（TRAE Work brand-600），用于 AI 相关的强调元素（10 级色阶 50–900）
- **Hover 态**: `#6a6fff` (brand-500)
- **Neutral (TRAE Work brand-grey)**: `#fafafa` ~ `#171717` — 文字 / 辅助色（10 级色阶）
- **Status**: Success (`#15a877`), Warning (`#e27900`), Alert (`#fea900`), Error (`#e8463a`), Info (`#2f74ff`) — 均含 surface 变体
- **Accent Coral**: `#b8897e` — 辅助强调色（低饱和度，10 级色阶）
- **Accent Amber**: `#c0a068` — 警告 / 高亮（低饱和度，10 级色阶）
- **Accent Teal**: `#4d9882` — 用于多彩 tag / chip（低饱和度）
- **Accent Cyan**: `#5098d0` — 用于多彩 tag / chip（低饱和度）
- **Accent Violet**: `#887acc` — 用于多彩 tag / chip（低饱和度）
- **Surface**: M3 风格层级，从 `surface-container-lowest` 到 `surface-container-highest`

> 完整色阶定义见 [`colors_and_type.css`](colors_and_type.css)。

### 字体（与 TRAE Work 完全一致）

- **Display / Heading**: SF Pro / PingFang SC
- **Body**: SF Pro Text / PingFang SC
- **Metric**: Inter
- **Mono**: JetBrains Mono

#### 排版阶梯

| 级别 | 大小 | 字重 | 用途 |
|------|------|------|------|
| display | 52px | 600 | 超大标题（极少在移动端使用） |
| display-sm | 40px | 600 | 大标题 |
| h1 | 32px | 600 | 页面主标题 |
| h2 | 28px | 600 | 区块标题 |
| h3 | 24px | 600 | 卡片标题 |
| h4 | 20px | 600 | 子标题 |
| h-lg | 22px | 600 | 大号标题 |
| h-md | 20px | 600 | 中号标题 |
| h-sm | 16px | 600 | 小号标题 |
| h-xs | 13px | 600 | 超小标题 / 角色标签 |
| h-2xs | 12px | 600 | 标签文字 |
| h-3xs | 11px | 600 | 最小标题 |
| body-lg | 18px | 400 | 大号正文 |
| body-base | 14px | 400 | 基础正文 |
| body-base-strong | 14px | 500 | 加粗正文 |
| body-md | 12px | 400 | 中号正文 |
| body-sm | 11px | 400 | 小号正文 |
| body-xs | 10px | 400 | 最小正文 |

CSS 类使用 `.sumi-` 前缀，如 `.sumi-h1`、`.sumi-body`。

### 间距（与 TRAE Work 一致）

连续编号 `spacer-0`(0px) ~ `spacer-13`(64px)，共 14 级。

| Token | 值 |
|-------|-----|
| `--space-0` | 0px |
| `--space-1` | 2px |
| `--space-2` | 4px |
| `--space-3` | 6px |
| `--space-4` | 8px |
| `--space-5` | 10px |
| `--space-6` | 12px |
| `--space-7` | 16px |
| `--space-8` | 20px |
| `--space-9` | 24px |
| `--space-10` | 32px |
| `--space-11` | 40px |
| `--space-12` | 48px |
| `--space-13` | 64px |

### 圆角（与 TRAE Work 一致）

从 2px 到 32px + full(9999px)，共 14 级：2/4/6/8/10/12/16/20/24/32/full。

常用值：`radius-8`(按钮/chip)、`radius-10`(日期 chip)、`radius-12`(输入框)、`radius-16`(卡片)、`radius-20`(sheet 顶部)。

便携别名：`--radius-sm` = radius-8、`--radius-md` = radius-12、`--radius-lg` = radius-20、`--radius-xl` = radius-24、`--radius-card` = radius-16、`--radius-card-header` = radius-20。

### 阴影

5 级冷灰色阴影：

| Token | 用途 |
|-------|------|
| `--shadow-1` | Card |
| `--shadow-2` | Card Hover |
| `--shadow-3` | Float |
| `--shadow-4` | Modal |
| `--shadow-5` | Overlay |

### 动效

- **duration**: `fast`(150ms)、`normal`(250ms)、`slow`(400ms)
- **easing**: `standard`、`decelerate`、`accelerate`

## 组件清单（24 个）

### 导航 (4)

| 组件 | 说明 | 预览 |
|------|------|------|
| Tab Bar | 底部 3 Tab 导航 | component-tab-bar.html |
| App Bar | 顶部导航栏 | component-app-bar.html |
| Calendar Navigation | 圆角矩形日期 chip (radius-10)，整月横向滚动 | component-calendar-nav.html |
| Scroll to Bottom | 聊天列表悬浮回底按钮 | component-scroll-to-bottom.html |

### 输入 (7)

| 组件 | 说明 | 预览 |
|------|------|------|
| Button | 主/次/文字/图标/危险 5 种变体 | component-button.html |
| Input | 单行/搜索/多行 3 种变体 | component-input.html |
| Toggle | iOS 风格开关 | component-toggle.html |
| Suggestion Chip | AI 建议提示 pill | component-suggestion-chip.html |
| Action Chip | 操作按钮（润色/项目/定时/复制） | component-action-chip.html |
| Chat Input | pill 输入框 + 右侧发送按钮（无左侧图标），长按语音输入 | component-chat-input.html |
| Send Button | 圆形发送按钮 | component-send-button.html |

### 数据展示 (7)

| 组件 | 说明 | 预览 |
|------|------|------|
| Todo Card | 待办瀑布流卡片 | component-todo-card.html |
| Todo Chip | pending 态左侧空心圆圈（transparent + border，点击可完成），completed 态实心 check + 划线 + muted | component-todo-chip.html |
| Chat Bubble | 对话气泡（含 streaming/reasoning），时间戳显示在用户气泡上方居中 | component-chat-bubble.html |
| Avatar | 用户头像（含在线状态） | component-avatar.html |
| Badge | 角标/通知红点 | component-badge.html |
| Empty State | 空状态占位 | component-empty-state.html |
| Collapsible Section | 可折叠区域 | component-collapsible-section.html |

### 浮层 (2)

| 组件 | 说明 | 预览 |
|------|------|------|
| Bottom Sheet | 底部弹窗（5 种变体） | component-bottom-sheet.html |
| Dialog | 模态确认/提示弹窗 | component-dialog.html |

### 反馈 (4)

| 组件 | 说明 | 预览 |
|------|------|------|
| Toast | 底部轻提示 | component-toast.html |
| Divider | 分割线 | component-divider.html |
| Drag Handle | Sheet 拖拽把手 | component-drag-handle.html |
| Voice Hint Bar | 语音录制状态提示 | component-voice-hint-bar.html |

## 图标

Outline 风格，1.5px stroke，24x24 viewBox，`currentColor`。

共 30 个图标，分为 5 类：

- **导航 (6)**: arrow-back, arrow-right, menu, close, more-vertical, expand-more
- **操作 (8)**: add, edit, delete, check, search, filter, send, copy
- **状态 (4)**: bell, bell-off, check-circle, alert-circle
- **功能 (8)**: calendar, chat, attach, mic, image, settings, tune, auto-awesome
- **特殊 (4)**: circle, circle-filled, push-pin, schedule

## 文件结构

```
sumi-1/
├── colors_and_type.css    # Token 定义（CSS 变量 + 排版类）
├── components.css         # 组件样式
├── css.json               # Token 结构化 JSON
├── metadata.json           # 元数据（系统管理）
├── README.md               # 本文档
├── SKILL.md                # AI 消费规则
├── components/
│   ├── index.json          # 组件索引
│   ├── button.json         # 每个组件的详细定义
│   ├── input.json
│   ├── ... (共 24 个)
├── icons/
│   ├── index.json          # 图标索引
│   ├── arrow-back.svg      # 每个图标的 SVG
│   ├── ... (共 30 个)
└── preview/                 # 组件预览 HTML
    ├── component-calendar-nav.html
    ├── component-chat-bubble.html
    ├── component-chat-input.html
    ├── component-suggestion-chip.html
    └── component-todo-chip.html
```

## 命名约定

- **Token**: `--category-name`（如 `--primary-600`、`--font-size-body-base`）
- **组件 slug**: kebab-case（如 `chat-input`、`todo-card`）
- **CSS 类**: `.sumi-` 前缀（如 `.sumi-h1`、`.sumi-body`）
- **图标**: kebab-case SVG 文件名

## 设计原则

1. **移动优先**：所有组件针对触屏交互优化，无 hover 态依赖
2. **Token 驱动**：组件样式通过 CSS 变量引用，不硬编码颜色/间距
3. **TRAE Work 对齐**：品牌色、色阶、字体、间距、圆角、阴影均与 TRAE Work 保持一致
4. **向后兼容**：保留 `--accent-*`、`--tertiary-*` 等 legacy 别名
5. **无障碍**：文字对比度 >= 4.5:1，交互区域最小 44px

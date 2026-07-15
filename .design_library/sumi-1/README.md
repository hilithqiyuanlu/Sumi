# Sumi Design System v2 — 从 Sumi App 反向提取的移动端设计系统

面向移动端 App 的设计系统，所有 Token 和组件规范直接从 Sumi App 真实 Flutter 项目代码反向提取。只包含项目实际使用的 Token 和组件，无多余定义。品牌色为项目实际使用的 Indigo Blue (#4758E0)，字体为 PingFang SC，遵循 iOS 原生设计语言。

## 设计理念

- **真实项目驱动**：设计系统是 Flutter 项目的"影子"——每个 Token 值都来自真实代码，不是从外部设计规范推导的近似值
- **只含所需**：不预定义"可能用到"的 Token 或组件，只收录项目实际使用的部分
- **简洁克制**：白色基底 + Indigo Blue 点缀，信息密度适中；非 primary 色彩均使用低饱和度色调，避免鲜亮高饱和色干扰
- **温暖陪伴**：圆润的 `radius-card` (18px) 和 pill 形状传递友好感
- **智能辅助**：AI 对话是核心交互，组件围绕对话 + 任务展开

## Token 体系

### 色彩

#### Primary (Indigo Blue)

| Token | 值 | 用途 |
|-------|-----|------|
| `--primary` / `--primary-500` | `#4758E0` | 品牌主色，@primary 标注在 500 |
| `--primary-100` | 淡 Indigo（mint 色） | 用户气泡背景等 soft 场景 |
| `--primary-600` | `#3740C7` | Suggestion Chip 文字等深色场景 |

完整 10 级色阶 50-900 见 [`colors_and_type.css`](colors_and_type.css)。

#### Accent

| Token | 值 | 用途 |
|-------|-----|------|
| `--accent-coral` | `#DF7D6D` | 辅助强调色 |
| `--tertiary-amber` | `#EFAE3E` | 警告 / 高亮 |

#### Neutral (Cool Gray)

| Token | 值 |
|-------|-----|
| 最浅 | `#F7F8FA` |
| 最深 | `#0E1115` |

完整 10 级色阶 50-900 见 [`colors_and_type.css`](colors_and_type.css)。

#### Status

| Token | 值 | 用途 |
|-------|-----|------|
| `--success-default` | `#42B570` | 成功 |
| `--warning-default` | `#F1BA30` | 警告 |
| `--error-default` | `#D95D4F` | 错误 |
| `--info-default` | `#5292D4` | 信息 |

#### Project Colors（7 种项目标记色）

lemon, mint, lilac, cherry, sky, peach, sage -- 用于 Todo Card / 项目标记。

#### Semantic

| Token | 值 | 用途 |
|-------|-----|------|
| `--color-paper` | `#FFFFFF` | 页面/卡片底色 |
| `--color-ink` | `#0E1115` | 主文字色 |
| `--color-line` | `#EBEBEB` | 分割线/边框 |
| `--color-text-tertiary` | `#7F8D9F` | 三级辅助文字 |
| `--color-surface-chip` | `#EFF1F4` | Chip/标签背景 |
| `--color-mint` | `var(--primary-100)` | mint 色（= primary100） |
| `--color-mint-deep` | `var(--primary-500)` | mint deep（= #4758E0） |

> 完整色阶定义见 [`colors_and_type.css`](colors_and_type.css)。

### 字体

- **Display / Heading / Body**: PingFang SC（项目实际使用，无 Inter/JetBrains Mono）

#### 排版阶梯（8 级 + 1 特殊）

| 级别 | 大小 | 字重 | 用途 |
|------|------|------|------|
| h3 | 24px | 800 | 卡片标题 |
| h4 | 20px | 800 | 子标题 |
| h-md | 18px | 600 | 中号标题 |
| h-sm | 16px | 700 | 小号标题 |
| h-xs | 13px | 600 | 超小标题 / 角色标签 |
| body-base | 14px | 500 | 基础正文 |
| body-md | 15px | 400 | 中号正文 |
| body-sm | 13px | 400 | 小号正文 |
| display-date | 22px | 700 | 日期显示（Calendar Nav 选中态） |

CSS 类使用 `.sumi-` 前缀，如 `.sumi-h3`、`.sumi-body-base`。

### 间距（12 级）

| Token | 值 |
|-------|-----|
| `--space-0` | 0px |
| `--space-1` | 2px |
| `--space-2` | 4px |
| `--space-3` | 6px |
| `--space-4` | 8px |
| `--space-5` | 10px |
| `--space-6` | 12px |
| `--space-7` | 14px |
| `--space-8` | 16px |
| `--space-9` | 20px |
| `--space-10` | 24px |
| `--space-11` | 32px |
| `--space-12` | 48px |

### 圆角（6 级 + pill）

2/4/8/12/18/20 + pill(9999px)。

便携别名：`--radius-sm` = 8px、`--radius-md` = 12px、`--radius-card` = 18px、`--radius-card-header` = 20px、`--radius-pill` = 9999px。

### 阴影（2 级）

基于 `rgba(14,17,21,...)` 冷灰色系：

| Token | 用途 |
|-------|------|
| `--shadow-1` | Card |
| `--shadow-2` | Card Hover |

### 动效

- **duration**: `fast`(150ms)、`normal`(250ms)、`slow`(400ms)
- **easing**: `standard`、`decelerate`、`accelerate`

## 组件清单（12 个）

### 导航 (5)

| 组件 | 说明 | 预览 |
|------|------|------|
| Tab Bar | 底部 3 Tab 导航 | component-tab-bar.html |
| App Bar | 顶部导航栏 | component-app-bar.html |
| Calendar Navigation | 52x72 chip，radiusCard(18px)，selected=mintDeep(#4758E0)，整月横向滚动 | component-calendar-nav.html |
| Scroll to Bottom | 聊天列表悬浮回底按钮 | component-scroll-to-bottom.html |
| Side Drawer | 左侧抽屉导航，含用户信息、项目列表、设置入口 | component-side-drawer.html |

### 输入 (2)

| 组件 | 说明 | 预览 |
|------|------|------|
| Suggestion Chip | surfaceChip 背景，primary600(#3740C7) 文字，pill 形状 | component-suggestion-chip.html |
| Chat Input | 左侧模式切换按钮(44x44) + pill 输入框 + 胶囊内发送按钮(44x44)，backdrop-filter blur(24)，bg white@82% | component-chat-input.html |

### 数据展示 (3)

| 组件 | 说明 | 预览 |
|------|------|------|
| Todo Chip | pending 态左侧空心圆圈（transparent + border，点击可完成），completed 态实心 check + muted 文字（无 line-through），padding 10px 14px，15px w500 | component-todo-chip.html |
| Chat Bubble | 用户右上小圆角、AI 左上小圆角，maxWidth 72%，无角色标签，时间戳 M/D HH:MM | component-chat-bubble.html |
| Empty State | 空状态占位 | component-empty-state.html |

### 浮层 (1)

| 组件 | 说明 | 预览 |
|------|------|------|
| Bottom Sheet | 底部弹窗（5 种变体） | component-bottom-sheet.html |

### 反馈 (1)

| 组件 | 说明 | 预览 |
|------|------|------|
| Drag Handle | Sheet 拖拽把手 | component-drag-handle.html |

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
│   ├── index.json          # 组件索引（12 个）
│   ├── app-bar.json
│   ├── bottom-sheet.json
│   ├── calendar-nav.json
│   ├── chat-bubble.json
│   ├── chat-input.json
│   ├── drag-handle.json
│   ├── empty-state.json
│   ├── scroll-to-bottom.json
│   ├── side-drawer.json
│   ├── suggestion-chip.json
│   ├── tab-bar.json
│   └── todo-chip.json
├── icons/
│   ├── index.json          # 图标索引
│   └── ... (共 30 个 SVG)
└── preview/                 # 组件预览 HTML（12 个）
    ├── component-app-bar.html
    ├── component-bottom-sheet.html
    ├── component-calendar-nav.html
    ├── component-chat-bubble.html
    ├── component-chat-input.html
    ├── component-drag-handle.html
    ├── component-empty-state.html
    ├── component-scroll-to-bottom.html
    ├── component-side-drawer.html
    ├── component-suggestion-chip.html
    ├── component-tab-bar.html
    └── component-todo-chip.html
```

## 命名约定

- **Token**: `--category-name`（如 `--primary-500`、`--font-size-body-base`）
- **组件 slug**: kebab-case（如 `chat-input`、`side-drawer`）
- **CSS 类**: `.sumi-` 前缀（如 `.sumi-h3`、`.sumi-body-base`）
- **图标**: kebab-case SVG 文件名

## 设计原则

1. **真实代码驱动**：所有 Token 值来自 Flutter 项目源码，非外部规范推导
2. **移动优先**：所有组件针对触屏交互优化，无 hover 态依赖
3. **Token 驱动**：组件样式通过 CSS 变量引用，不硬编码颜色/间距
4. **只含所需**：不预定义未使用的 Token、组件或字体
5. **无障碍**：文字对比度 >= 4.5:1，交互区域最小 44px

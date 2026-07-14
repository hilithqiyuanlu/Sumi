# Sumi UI/UX 自检与优化计划

## 概要

对当前 Sumi Flutter 项目做一轮全面 UI/UX 自检，对比 sumi-1 设计系统规范和 Google Material 3 设计准则，修复视觉一致性、层次感、间距节奏、交互细节等问题。

---

## 当前状态分析

### 架构
- 单页 `HomePage` + `SideDrawer`（无 Bottom Nav）
- `TodoChipCarousel`（横向 chip 条）+ `TodoGrid`（masonry 瀑布流卡片）双视图
- `ChatInput` 带毛玻璃效果和语音输入
- `BubbleBarrage` 弹幕动画
- `VerdictBadge` / `ScoreBar` 评估组件

### Token 系统
- Indigo Blue 主色 + Google 冷灰中性色 — 已对齐
- 项目色 lemon/peach/sage 已改为冷色调 — 已对齐
- shadow1~5 冷黑色阴影 — 已对齐

---

## 发现的问题清单

### P0 — 视觉一致性

#### 1. `_selectCenterDate` 中 `itemExtent` 和 `_checkCenterChange` 不一致
- **文件**: `date_strip.dart` L161/179
- **问题**: `_checkCenterChange` 用 `60.0`，`_selectCenterDate` 用 `62.0`，但 `_scrollToSelected` 用 `60.0`（52+8）。三者不一致导致日期选择偏移
- **修复**: 统一全部为 `60.0`

#### 2. VerdictBadge 使用了 `warning_amber_rounded` 图标
- **文件**: `verdict_badge.dart` L35
- **问题**: `Icons.warning_amber_rounded` 违反了设计系统的"不使用 `_rounded` 后缀"规则
- **修复**: 改为 `Icons.warning_amber`

#### 3. SideDrawer 缺少遮罩层
- **文件**: `home_page.dart`（SideDrawer 使用处）
- **问题**: 抽屉打开时，后面的内容仍然可交互，没有半透明遮罩阻挡
- **修复**: 在 SideDrawer 下方增加一个 `GestureDetector` + 半透明黑色遮罩层

#### 4. ChatInput 录音态边框透明度偏低
- **文件**: `chat_input.dart` L298
- **问题**: 录音边框 `mintDeep.withValues(alpha: 0.45)` 太淡，用户难以察觉正在录音
- **修复**: 提高到 `0.6`，同时录音提示条加一个脉冲红色圆点指示器

### P1 — 层次与间距

#### 5. TodoGrid 空状态文案位置和样式
- **文件**: `todo_grid.dart` L25-30
- **问题**: 空状态文字 `还没有事项，在下方输入框创建吧` 直接居中，没有图标引导，字号偏小
- **修复**: 增加一个 `auto_awesome` 图标（48px, primary100 色），文案字号从 14 调为 15，间距 s8

#### 6. SideDrawer 当前会话高亮对比度不够
- **文件**: `side_drawer.dart` L169
- **问题**: 当前会话使用 `primary50` 背景色，在白色背景上对比度极低（`#EEF1FE` vs `#FFFFFF`），几乎看不出选中态
- **修复**: 改为 `primary100.withValues(alpha: 0.4)` 提供更明显的选中反馈

#### 7. Settings 页 section 间距节奏
- **文件**: `settings_body.dart` L146-152
- **问题**: "Sumi 记忆" section header 和卡片之间只有 `s12` 间距，而 API section header 和卡片之间也是 `s12`。但 "Sumi 记忆" 与 API 密钥 section 之间是 `s24`。整体节奏正确，但 "思考模式" / "开发者" section header 与卡片之间只有 `s8`，和其他 section 的 `s12` 不一致
- **修复**: L152 和 L168 的 `s8` 统一改为 `s12`

#### 8. TodoEditSheet 底部间距不足
- **文件**: `todo_edit_sheet.dart` L360
- **问题**: 整个 Column 底部只有 `s8`，在安全区内显得太紧凑
- **修复**: 改为 `s16`

### P2 — 交互细节

#### 9. SuggestionChip 缺少按压反馈
- **文件**: `suggestion_strip.dart` L53-71
- **问题**: chip 使用 `InkWell` 但没有 `splashColor` 或视觉按压效果，点击时没有明显的视觉反馈
- **修复**: 已经用了 `InkWell`，但 `Material` 的 `color` 是 `surfaceChip`。改为在 `InkWell` 上添加自定义 splash: `overlayColor: WidgetStatePropertyAll(primary500.withValues(alpha: 0.08))`

#### 10. BubbleBarrage 缺少淡出效果
- **文件**: `bubble_barrage.dart` L96
- **问题**: opacity 计算 `(1.0 - controller.value)` 只是线性衰减，气泡消失前没有加速淡出
- **修复**: 将 opacity 计算改为 `(1.0 - Curves.easeIn.transform(controller.value))`，让消失更自然

#### 11. ChatBubble 中 AnimatedBuilder 兼容性
- **文件**: `chat_bubble.dart` L229
- **问题**: 使用 `AnimatedBuilder` — Flutter 3.22+ 中 `AnimatedBuilder` 已被弃用，应改为 `AnimatedWidget` 或使用 `ListenableBuilder`
- **修复**: 改为 `SingleTickerProviderStateMixin` + `AnimatedBuilder`（实际上 Flutter 确实有 `AnimatedBuilder`，这是正确的。不需要修改）

---

## 执行计划

**批次 1 (P0)**: 4 项必须修复
1. DateStrip itemExtent 统一为 60.0
2. VerdictBadge 图标去掉 `_rounded`
3. SideDrawer 遮罩层
4. ChatInput 录音态增强

**批次 2 (P1)**: 4 项建议修复
5. TodoGrid 空状态增加图标
6. SideDrawer 选中态对比度
7. Settings section 间距统一
8. EditSheet 底部间距

**批次 3 (P2)**: 2 项锦上添花
9. SuggestionChip 按压反馈
10. BubbleBarrage 淡出曲线

---

## 验证

每批次完成后 `flutter analyze` 确认无编译错误。

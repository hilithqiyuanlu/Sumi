# Sumi UI/UX 自检与优化计划

## 概要

对当前 Sumi Flutter 项目做一轮全面 UI/UX 自检，对比 sumi-1 设计系统规范，找出视觉不一致、层次感不足、交互细节缺失的问题并逐一修复。

---

## 当前状态分析

### 架构变化（相比上次优化）
- 去掉了 Bottom Navigation（3-tab），改为**单页 HomePage + SideDrawer**
- 新增 `SuggestionStrip`（建议 chip 条）、`BubbleBarrage`（气泡弹幕）、`VerdictBadge`（判定徽章）、`ScoreBar`（分数条）
- ChatInput 增加了毛玻璃效果
- TodoCard 从 masonry grid 改为普通 list/chip 展示

### 发现的问题清单

---

## P0 — 视觉一致性（必须修）

### 1. TodoCard 缺少 shadow — 太平
- **文件**: `todo_card.dart`
- **问题**: 卡片只有 0.5px 微边框，没有 `shadow1`，在纯白背景上缺少层次感
- **方案**: 为非项目色卡片增加 `shadow1`；项目色卡片保持无 shadow（有色背景已足够区分）

### 2. ChatBubble 用户气泡的 borderRadius 不对称
- **文件**: `chat_bubble.dart`
- **问题**: 用户气泡 `topLeft: 20, topRight: 20, bottomLeft: 4, bottomRight: 20`，但 `bottomRight` 应该也是 4 才能形成正确的"尾巴"效果（用户在右侧）
- **方案**: 用户气泡 `bottomRight: 4`，AI 气泡 `bottomLeft: 4`（已经是这样）

### 3. ChatInput 录音态视觉反馈不够明显
- **文件**: `chat_input.dart`
- **问题**: 录音态有脉冲动画但整体视觉差异不够大，用户可能意识不到正在录音
- **方案**: 录音态增加一个更大的指示器（红色圆点 + "正在录音..." 文字），而不仅仅是边框变粗

### 4. DateStrip 选中态与今日态视觉区分度不够
- **文件**: `date_strip.dart`
- **问题**: 选中态是 `primary500` 实心，今日态是 `primary100 @ 50%`，两者在视觉上还行但 chip 太小（54x72），日期数字 22px 在 54px 宽的 chip 中偏大，显得拥挤
- **方案**: 日期 chip 宽度从 54 调整为 48，数字字号从 22 调为 20，增加呼吸感；或者反过来加大 chip 到 56。需确认实际效果

---

## P1 — 层次与间距（建议修）

### 5. HomePage 空状态区域缺少视觉引导
- **文件**: `home_page.dart`
- **问题**: 空状态只有文字提示，缺少图标或插图引导用户开始使用
- **方案**: 空状态添加一个居中的轻量图标（如 `auto_awesome` at 48px, primary100 色），配合文字提示

### 6. SideDrawer 毛玻璃效果
- **文件**: `side_drawer.dart`
- **问题**: 侧边抽屉没有毛玻璃背景效果，遮挡内容时显得突兀
- **方案**: 在 Container decoration 中增加 `BackdropFilter` + `Colors.white.withOpacity(0.85)` 背景，和 ChatInput 的毛玻璃风格统一

### 7. Settings 页卡片间距不统一
- **文件**: `settings_body.dart`
- **问题**: "苏米记忆" section 和 API section 之间的间距与其他 section 不一致
- **方案**: 统一所有 section 之间的间距为 `s16`

### 8. TodoEditSheet 内部间距
- **文件**: `todo_edit_sheet.dart`
- **问题**: action chips 行和保存按钮之间缺少分隔，视觉上挤在一起
- **方案**: 在 action chips 和 buttons 之间增加 12px 间距

---

## P2 — 交互细节（锦上添花）

### 9. BubbleBarrage 入场动画
- **文件**: `bubble_barrage.dart`
- **问题**: 气泡弹幕从底部飞出，但没有淡出效果，消失太突兀
- **方案**: 在消失前增加 `FadeOut` 动画（200ms）

### 10. VerdictBadge 颜色对比度
- **文件**: `verdict_badge.dart`
- **问题**: 需确认 badge 颜色在浅色背景上有足够对比度
- **方案**: 检查并确保所有 badge 变体的文字颜色有 4.5:1 对比度

### 11. ScoreBar 渐变色方向
- **文件**: `score_bar.dart`
- **问题**: 确认渐变方向是否从左到右（直觉方向）
- **方案**: 如不是，改为 `LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight)`

### 12. SuggestionStrip chip 的按压反馈
- **文件**: `suggestion_strip.dart`
- **问题**: 需确认 chip 点击有视觉反馈（设计系统要求 brightness(0.95)）
- **方案**: 如果没有，添加 `InkWell` + `ColorFiltered` 按压动画

---

## 执行计划

按优先级分批执行：

**批次 1（P0）**: 4 个必须修复项 — TodoCard shadow、ChatBubble borderRadius、ChatInput 录音指示、DateStrip 尺寸
**批次 2（P1）**: 4 个建议修复项 — 空状态图标、SideDrawer 毛玻璃、Settings 间距、EditSheet 间距
**批次 3（P2）**: 4 个锦上添花项 — BubbleBarrage 动画、VerdictBadge 对比度、ScoreBar 方向、SuggestionStrip 按压

---

## 验证步骤

1. 每批次修改后 `flutter analyze` 确保无编译错误
2. 逐项对比设计系统 JSON 规范确认一致性
3. 关注：纯白背景上的层次感、选中/未选中态的区分度、间距的节奏感

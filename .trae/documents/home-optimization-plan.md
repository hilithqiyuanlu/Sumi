# 首页优化开发计划

## Summary

基于前期代码全面检查，本次优化重点修复核心功能缺失和 UI/UX 问题。文案类保持当前实现，不强行对齐设计系统 mock 数据。

## Priority 1: 核心功能修复

### 1. 键盘收起逻辑
**文件**: `lib/features/home/home_page.dart`
**问题**: 点击对话区域空白处不会收起键盘
**方案**: 在消息列表区域添加 `GestureDetector`，点击时调用 `FocusScope.of(context).unfocus()`

### 2. 月视图展开功能
**文件**: `lib/features/home/home_page.dart`, `lib/features/calendar/month_view_sheet.dart`
**问题**: `DateStrip(onExpandMonth: () {})` 回调为空
**方案**: 
- 在 `HomePage` 中添加 `_monthSheetOpen` 状态
- 实现 `_toggleMonthSheet()` 方法
- 使用 `showModalBottomSheet` 展示 `MonthViewSheet`

### 3. 设置面板全屏 + 返回按钮
**文件**: `lib/features/home/settings_panel.dart`
**问题**: 
- 占屏 5/6，应全屏
- 右上角关闭按钮应改为左上角返回按钮
**方案**: 
- 改为全屏 `Scaffold` 结构
- 顶部添加 `AppBar`，左侧返回按钮
- 移除 `AnimatedPositioned`，改为完整页面

### 4. 日历导航栏去卡片化
**文件**: `lib/features/calendar/date_strip.dart`
**问题**: `DateStrip` 被包裹在白色卡片容器中
**方案**: 移除 `Container` 的白色背景和圆角，改为透明背景

## Priority 2: UI/UX 优化

### 5. 建议胶囊高度调整
**文件**: `lib/features/home/suggestion_strip.dart`
**问题**: 高度 48px，应降低到 36px
**方案**: 容器高度改为自适应，padding 改为 `8px 16px`

### 6. 输入框液态玻璃效果
**文件**: `lib/features/chat/chat_input.dart`
**问题**: 缺少 `backdropFilter` + `blur` 效果
**方案**: 
- 添加 `backdropFilter: BlurEffect(blur: 20)`
- 添加软阴影
- 调整背景透明度为 0.85

### 7. 恢复工具面板入口
**文件**: `lib/features/home/home_page.dart`
**问题**: 原 `ChatPage` 的扳手菜单入口丢失
**方案**: 在首页添加工具按钮入口（可放在侧边栏或顶部）

### 8. 滚动到底部按钮
**文件**: `lib/features/home/home_page.dart`
**问题**: 消息列表长时无法快速滚动到底部
**方案**: 添加浮动滚动按钮，当列表不在底部时显示

## Priority 3: 代码清理

### 9. 移除未使用的 import
**文件**: 各组件文件
**问题**: 部分文件存在未使用的 import
**方案**: 运行 `flutter analyze` 检查并清理

## Files to Modify

| 文件 | 修改内容 | 优先级 |
|------|----------|--------|
| `lib/features/home/home_page.dart` | 键盘收起、月视图展开、滚动按钮、工具入口 | P1 |
| `lib/features/calendar/date_strip.dart` | 移除卡片背景 | P1 |
| `lib/features/home/settings_panel.dart` | 全屏化、返回按钮 | P1 |
| `lib/features/chat/chat_input.dart` | 液态玻璃效果 | P2 |
| `lib/features/home/suggestion_strip.dart` | 降低胶囊高度 | P2 |

## Implementation Steps

### Step 1: 键盘收起 + 月视图展开
修改 `home_page.dart`，添加键盘收起逻辑和月视图展开

### Step 2: 日历导航栏去卡片化
修改 `date_strip.dart`，移除白色背景容器

### Step 3: 设置面板全屏化
重写 `settings_panel.dart`，改为全屏 Scaffold

### Step 4: 建议胶囊高度调整
修改 `suggestion_strip.dart`，降低高度

### Step 5: 输入框液态玻璃效果
修改 `chat_input.dart`，添加 backdropFilter

### Step 6: 滚动到底部按钮 + 工具入口
修改 `home_page.dart`，添加浮动按钮和工具入口

### Step 7: 代码清理
运行 `flutter analyze` 检查并清理

## Risk Handling

| 风险 | 处理方案 |
|------|----------|
| 设置面板全屏化可能影响动画效果 | 使用 `PageRoute` 替代 `AnimatedPositioned` |
| 键盘收起可能影响输入体验 | 仅在点击消息区域时收起，不影响输入框本身 |
| 液态玻璃效果在旧设备上可能卡顿 | 使用 `BackdropFilter` 并限制 blur 半径 |

## Verification Steps

1. 编译通过：`flutter analyze` 无 error
2. 运行应用后验证：
   - 点击消息区域空白处键盘收起
   - 点击日历拖拽把手展开月视图
   - 设置面板全屏显示，左上角有返回按钮
   - 日历导航栏透明背景
   - 建议胶囊紧贴输入框，高度降低
   - 输入框有液态玻璃效果
   - 长列表时有滚动到底部按钮
   - 工具面板可正常打开

## Notes

- 文案类保持当前实现，不强制对齐设计系统
- 设计系统仅作为视觉参考，实际实现以用户需求为准
- 滚动到底部按钮和工具入口根据空间情况决定最终位置

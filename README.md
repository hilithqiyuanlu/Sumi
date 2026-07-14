# Sumi（米糖）

一个**本地优先的 AI 自学助手**，帮你管理事项、追踪学习项目，内建 AI 对话助手。

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2013%2B-lightgrey" alt="platform">
  <img src="https://img.shields.io/badge/framework-Flutter-02569B?logo=flutter" alt="flutter">
  <img src="https://img.shields.io/badge/API-DeepSeek-4B6BFB" alt="deepseek">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- **📋 Keep 风格事项网格** — Masonry 瀑布流布局，Pin 置顶 / 完成态 / 长按拖拽排序 / 拖到日期分配
- **🤖 AI 智能拆分与润色** — 输入 >18 字触发 DeepSeek 拆分；编辑面板一键 AI 润色标题
- **💬 米糖 Tab** — 内建 AI 对话助手，流式输出、多会话管理、Markdown 渲染、Thinking 模式开关
- **🔧 Function Calling** — AI 可调用工具读写 todo / memory，支持 Agent 自主循环
- **🛠 Wrench 工具面板** — 对话页侧边面板，整合语音输入、工具调用等快捷操作
- **📅 日历导航** — 折叠态日期条 + 展开月视图，垂直拖拽手势切换
- **📂 项目系统** — 最多 3 个学习项目，AI 生成月计划，月卡解锁机制追踪进度
- **🔐 本地优先** — SQLite 持久化，API Key 走 Secure Storage，无需服务器

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.x |
| 状态管理 | ChangeNotifier + InheritedNotifier |
| 持久化 | SQLite（`sqflite`） + Secure Storage |
| AI 接口 | DeepSeek Chat API（流式 SSE / 非流式 / Function Calling） |
| 语音输入 | iOS Speech Recognition |
| 搜索 | Tavily Search API（内联于 AiService） |

## 快速开始

```bash
# 1. 克隆项目
git clone git@github.com:hilithqiyuanlu/Sumi.git
cd Sumi

# 2. 安装依赖
flutter pub get

# 3. 运行（需连接 iOS 设备或模拟器）
flutter run

# 发布到 iPhone
flutter run --release
```

> **注意**：首次运行需要在「设置」Tab 中配置 [DeepSeek API Key](https://platform.deepseek.com/)，否则 AI 拆分、润色、对话功能不可用。

## 项目结构

```
lib/
├── main.dart                         # 入口，初始化 store + 数据库
├── main_shell.dart                   # 3 Tab 底部导航（事项 / 米糖 / 设置）
├── sumi_scope.dart                   # InheritedNotifier 依赖注入
├── models/models.dart                # 数据模型
├── store/
│   ├── sumi_store.dart               # 全局 ChangeNotifier
│   ├── sumi_store_todos.dart         # 事项 CRUD + 排序
│   ├── sumi_store_projects.dart      # 项目/月卡 + AI 规划
│   ├── sumi_store_chat.dart          # 对话状态 + Agent 循环
│   └── sumi_store_persist.dart       # 快照持久化
├── data/
│   ├── local_database.dart           # SQLite 数据库
│   └── chat_database.dart            # 对话数据 CRUD
├── services/
│   ├── ai_service.dart               # DeepSeek API（拆分/润色/规划/对话/搜索）
│   ├── tool_executor.dart            # Function Calling 工具执行
│   ├── voice_input_service.dart      # iOS 语音识别
│   └── secure_settings_store.dart    # Keychain 安全存储
├── theme/app_theme.dart              # Sumi 设计系统（Design Tokens）
└── features/
    ├── todos/                        # 事项网格、卡片、输入栏、编辑面板
    ├── chat/                         # 对话页面、气泡、输入、会话列表、Wrench 面板
    ├── calendar/                     # 日期条、月历、月视图展开层
    ├── projects/                     # 项目卡、月卡 Pager、项目编辑器
    ├── settings/                     # API Key 配置、Thinking 开关、清除数据
    └── shared/                       # 共享组件（可折叠区域、拖拽把手）
```

## License

MIT

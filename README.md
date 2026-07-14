# Sumi

一个 **AI 原生**的个人效率伴侣 — 以对话为主要界面，融合事项管理、学习规划与知识记忆。

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2013%2B-lightgrey" alt="platform">
  <img src="https://img.shields.io/badge/framework-Flutter-02569B?logo=flutter" alt="flutter">
  <img src="https://img.shields.io/badge/AI-DeepSeek-4B6BFB" alt="deepseek">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- **💬 AI 对话** — 首页即对话，流式输出 Markdown 渲染，支持 Thinking 过程展示与 Function Calling 工具调用
- **📋 事项管理** — 输入 >16 字自动触发 AI 智能拆分；支持置顶、完成态、长按排序、拖拽分配日期、编辑面板 AI 润色
- **📂 学习项目** — 最多 3 个项目，AI 生成月度学习计划，月卡解锁机制追踪进度
- **🧠 智能评估与规划** — 输入学习目标，AI 联网搜索 + 8 维度评分，生成分阶段学习计划
- **📅 日历导航** — 折叠日期条 + 展开月视图，垂直拖拽手势自然切换
- **🎤 语音输入** — iOS 原生语音识别，长按说话松开发送
- **🧭 侧边抽屉** — 左滑唤出会话列表，新建 / 切换 / 删除对话
- **🔐 本地优先** — SQLite 持久化，API Key 走 Keychain 安全存储，无需服务器

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.x |
| 状态管理 | ChangeNotifier + InheritedNotifier |
| 持久化 | SQLite（sqflite） + Secure Storage |
| AI | DeepSeek Chat API（流式 SSE / 非流式 / Function Calling） |
| 搜索 | Tavily Search API |
| 语音 | iOS Speech Recognition |
| 设计 | Sumi Design System（Indigo 配色，Design Tokens） |

## 快速开始

```bash
# 1. 克隆
git clone git@github.com:hilithqiyuanlu/Sumi.git
cd Sumi

# 2. 安装依赖
flutter pub get

# 3. 运行
flutter run              # Debug
flutter run --release    # 发布到 iPhone
```

> 首次使用需在设置中配置 [DeepSeek API Key](https://platform.deepseek.com/)，AI 功能依赖此项。

## 项目结构

```
lib/
├── main.dart                            # 应用入口
├── sumi_scope.dart                      # InheritedNotifier 依赖注入
├── models/models.dart                   # 全部数据模型
├── theme/app_theme.dart                 # Sumi 设计系统
├── utils/utils.dart                     # 工具函数
├── store/
│   ├── sumi_store.dart                  # 全局状态（ChangeNotifier）
│   ├── sumi_store_todos.dart            # 事项 CRUD + 排序 + AI 拆分
│   ├── sumi_store_projects.dart         # 项目 / 月卡 + AI 规划
│   ├── sumi_store_chat.dart             # 对话状态 + Agent 循环
│   └── sumi_store_persist.dart          # 快照持久化
├── data/
│   ├── local_database.dart              # SQLite 主库
│   └── chat_database.dart               # 对话数据 CRUD
├── services/
│   ├── ai_service.dart                  # DeepSeek API 封装（对话 / 拆分 / 规划 / 搜索）
│   ├── tool_executor.dart               # Function Calling 工具执行
│   ├── voice_input_service.dart         # iOS 语音识别
│   ├── goal_assessor.dart               # 目标评估（搜索 + 多维分析）
│   ├── plan_generator.dart              # 学习计划生成器
│   └── secure_settings_store.dart       # Keychain 安全存储
├── widgets/
│   ├── bubble_barrage.dart              # 弹幕加载动画
│   ├── score_bar.dart                   # 评估分数条
│   └── verdict_badge.dart               # 评估结论徽章
└── features/
    ├── home/                            # 首页、侧边抽屉、设置面板、建议条
    ├── chat/                            # 对话气泡、输入栏（对话 / 事项双模式）
    ├── todos/                           # 事项网格、卡片、输入、编辑、Chip 轮播、拆分确认
    ├── calendar/                        # 日期条、月历、月视图
    ├── projects/                        # 项目卡、月卡翻页、编辑器、评估 & 规划页
    ├── settings/                        # 设置页（API Key、Thinking 开关、用户昵称）
    └── shared/                          # 可折叠区域、拖拽把手
```

## License

MIT

# Sumi

一个 **AI 原生**的个人自学助手 — 以对话为主要界面，融合事项管理、学习规划与知识记忆。

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20Android-lightgrey" alt="platform">
  <img src="https://img.shields.io/badge/framework-Flutter-02569B?logo=flutter" alt="flutter">
  <img src="https://img.shields.io/badge/AI-DeepSeek-4B6BFB" alt="deepseek">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- **💬 AI 对话** — 首页即对话，流式输出 Markdown 渲染，支持 Thinking 过程展示与 Function Calling 工具调用；按日期组织对话，侧边抽屉切换/删除历史会话
- **📋 事项管理** — 输入 >16 字自动触发 AI 智能拆分；支持置顶、完成态、长按拖拽排序；关联项目的事项 Chip 显示项目主题色
- **📂 学习项目** — AI 生成月度学习计划，月卡解锁机制逐月推进；AI 凝练目标摘要作为卡片标题，支持项目主题色区分
- **🧠 智能评估与规划** — 输入学习目标，AI 联网搜索 + 8 维度评分，流式生成学习计划；统一生成管线（搜索→评估→确认→规划→校验→保存），支持取消/重试/跳过评估
- **📅 日历导航** — 折叠日期条 + 展开月视图，垂直拖拽手势自然切换；历史日期只读，仅可查看过往对话
- **🎤 语音输入** — 长按说话松开发送、上滑取消，支持连续识别与自动提交
- **🧭 侧边抽屉** — 左滑唤出会话列表，新建 / 切换 / 删除对话，支持置顶与自定义标题
- **🧠 用户模型** — USER_MODEL.md 替代旧 MEMORY.md，结构化五区段记忆（实时状态 / 核心记忆 / 领域画像 / 长期偏好 / 归档），HOT/WARM 分层注入对话上下文，Dice coefficient 去重合并，每周自动 AI 反思更新
- **📡 行为信号** — todo 创建/完成/编辑/拖拽、项目目标/水平/周期设定等 10 种信号自动采集，AI 通过 read_signals 工具查询历史模式
- **🛡️ AI 契约校验** — 所有 AI 结构化输出经 AiContracts 强校验（字段类型、长度、取值范围），非法输出自动拦截，防止脏数据落库
- **🔐 本地优先** — SQLite 持久化，API Key 走 Keychain 安全存储，无需服务器

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.x |
| 状态管理 | ChangeNotifier + InheritedNotifier（分域控制器） |
| 持久化 | SQLite（sqflite） + Secure Storage |
| AI | DeepSeek Chat API（流式 SSE / 非流式 / Function Calling） |
| 搜索 | Tavily Search API |
| 语音 | speech_to_text（iOS / Android） |
| 设计 | Sumi Design System（Indigo 配色，Design Tokens） |

## 快速开始

```bash
# 1. 克隆
git clone git@github.com:hilithqiyuanlu/Sumi.git
cd Sumi

# 2. 安装依赖
flutter pub get

# 3. 运行
flutter run              # Debug（iOS / Android）
flutter run --release    # 发布模式
```

> 首次使用需在设置中配置 [DeepSeek API Key](https://platform.deepseek.com/)，AI 功能依赖此项。

## 项目结构

```
lib/
├── main.dart                            # 应用入口
├── sumi_scope.dart                      # InheritedNotifier 依赖注入（分域监听）
├── models/models.dart                   # 全部数据模型
├── theme/app_theme.dart                 # Sumi 设计系统
├── utils/utils.dart                     # 工具函数
├── utils/haptics.dart                   # 统一触觉反馈（H 工具类）
├── store/
│   ├── sumi_store.dart                  # AppStore 应用协调器
│   ├── domain_controllers.dart          # 分域控制器（Todo/Project/Settings/Chat/Selection）
│   ├── sumi_store_todos.dart            # 事项 CRUD + 排序 + AI 拆分
│   ├── sumi_store_projects.dart         # 项目 / 月卡 + AI 规划管线
│   ├── sumi_store_chat.dart             # 对话状态 + Agent 循环
│   └── sumi_store_persist.dart          # 快照持久化 + 迁移
├── data/
│   ├── local_database.dart              # SQLite 主库（含 signals 表）
│   ├── chat_database.dart               # 对话数据 CRUD
│   └── signal_database.dart             # 信号数据持久化
├── services/
│   ├── ai_service.dart                  # AiTransport — DeepSeek HTTP 传输层
│   ├── ai_contracts.dart                # AI 输出契约校验（split/polish/plan/assess/suggestions/toolCall）
│   ├── ai_runtime.dart                  # AiRuntime — 组合 transport + structured/chat/search 三 facade
│   ├── chat_prompt_builder.dart         # 系统 prompt 组装（basePrompt + 上下文注入）
│   ├── prompt_context.dart              # 数据/指令分离封装（防 prompt 注入）
│   ├── tool_executor.dart               # Function Calling 工具执行（含记忆合并）
│   ├── voice_input_service.dart         # speech_to_text 语音识别
│   ├── goal_assessor.dart               # 目标评估（搜索 + 多维分析）
│   ├── plan_generator.dart              # 学习计划生成器（流式 + 降级 + 自动修复）
│   ├── project_generation.dart          # 项目生成协调器（搜索→评估→确认→规划→校验→保存）
│   ├── daily_planning_policy.dart       # 日计划业务规则（周期计数、月卡查询）
│   ├── user_model_service.dart          # USER_MODEL.md 读写 / 统计 / 合并 / 迁移
│   ├── signal_service.dart              # 信号采集 / 编辑区分 / 凝练还原保护
│   ├── snapshot_write_queue.dart        # 串行快照写入队列（仅保留最新待写状态）
│   └── secure_settings_store.dart       # Keychain 安全存储
├── widgets/
│   ├── score_bar.dart                   # 评估分数条
│   └── verdict_badge.dart               # 评估结论徽章
└── features/
    ├── home/                            # 首页、侧边抽屉、设置面板、建议条
    │   ├── home_page.dart
    │   ├── side_drawer.dart
    │   ├── settings_panel.dart
    │   └── suggestion_strip.dart
    ├── chat/                            # 对话气泡、输入栏（对话 / 事项双模式）
    │   ├── chat_bubble.dart
    │   └── chat_input.dart
    ├── todos/                           # 事项 Chip 轮播、编辑面板、拆分确认
    │   ├── todo_chip_carousel.dart
    │   ├── todo_edit_sheet.dart
    │   └── split_confirm_sheet.dart
    ├── calendar/                        # 日期条、月历、月视图
    │   ├── date_strip.dart
    │   ├── month_calendar.dart
    │   └── month_view_sheet.dart
    ├── projects/                        # 项目筛选栏、月卡翻页、编辑器、生成管线页
    │   ├── project_tabs.dart
    │   ├── month_card_pager.dart
    │   ├── project_editor_page.dart
    │   └── project_generation_page.dart
    ├── settings/                        # 设置页（API Key、用户模型编辑器、信号日志）
    │   ├── settings_body.dart
    │   ├── user_model_editor_page.dart
    │   └── signal_log_page.dart
    └── shared/                          # 拖拽把手
        └── drag_handle.dart
```

## License

MIT

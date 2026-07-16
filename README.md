# Sumi

一个 **AI 原生**的个人自学助手 — 以对话为主要界面，融合事项管理、学习规划与知识记忆。

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2016%2B%20%7C%20Android-lightgrey" alt="platform">
  <img src="https://img.shields.io/badge/framework-Flutter-02569B?logo=flutter" alt="flutter">
  <img src="https://img.shields.io/badge/AI-DeepSeek-4B6BFB" alt="deepseek">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- **💬 AI 对话** — 首页即对话，流式输出 Markdown，支持 Thinking 展示与 Function Calling（7 种工具）；中途可停止生成，设备时间自动注入以准确理解相对时间；按日期组织对话，侧边抽屉管理会话，支持置顶与自定义标题
- **📋 事项管理** — 长文本自动 AI 拆分；支持置顶、完成态、拖拽排序；关联项目的事项 Chip 显示对应主题色
- **📂 学习项目** — AI 生成月度学习计划，月卡解锁逐月推进，支持项目主题色区分
- **🧠 智能评估与规划** — 输入学习目标，AI 联网搜索 + 多维度评分，流式生成学习计划；支持从对话中直接启动；滚动窗口自动维护每日事项
- **📅 日历导航** — 折叠日期条 + 展开月视图，拖拽切换；历史日期只读可回顾
- **🎤 语音输入** — 长按说话松开发送、上滑取消，支持连续识别
- **🧠 用户记忆与信号** — 每次对话后自动提取偏好、目标及项目进度；操作行为自动采集为信号，AI 可查询历史模式
- **⏱️ 计时与闹钟** — AI 可在对话中创建倒计时或指定时刻闹钟，到期通过系统通知提醒，后台/锁屏也不会错过
- **📊 日程负载** — 自动检测事项密度，超负荷时生成调整建议，对话内卡片确认；后台时推送通知
- **🤖 端侧 AI** — 端侧嵌入模型提供混合检索，从历史对话中注入上下文；可选下载本地语言模型，无网络也能使用基础 AI
- **🏁 里程碑与每日复盘** — 识别学习突破与完成，沉淀为里程碑；每日复盘整理事项与记忆
- **🔐 本地优先** — SQLite 持久化，API Key 安全存储，无需服务器

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
│   ├── local_database.dart              # SQLite 主库（含 signals / memory / embedding 表）
│   ├── chat_database.dart               # 对话数据 CRUD
│   ├── signal_database.dart             # 信号数据持久化
│   ├── embedding_document_store.dart    # 本地嵌入向量文档存储
│   ├── study_timer_database.dart        # 学习计时持久化
│   └── schedule_proposal_database.dart   # 日程重排建议持久化
├── services/
│   ├── ai_service.dart                  # AiTransport — DeepSeek HTTP 传输层
│   ├── ai_contracts.dart                # AI 输出契约校验（split/polish/plan/weeklyTodos/assess/suggestions/toolCall）
│   ├── ai_runtime.dart                  # AiRuntime — 组合 transport + structured/chat/search/memoryExtraction facade
│   ├── chat_prompt_builder.dart         # 系统 prompt 组装（basePrompt + 上下文注入）
│   ├── prompt_context.dart              # 数据/指令分离封装（防 prompt 注入）
│   ├── chat_tool_registry.dart          # 工具注册中心 — 7 种工具的名称/Schema/分组集中管理
│   ├── tool_executor.dart               # Function Calling 工具执行
│   ├── voice_input_service.dart         # speech_to_text 语音识别
│   ├── goal_assessor.dart               # 目标评估（搜索 + 多维分析）
│   ├── plan_generator.dart              # 学习计划生成器（流式 + 降级 + 自动修复）
│   ├── project_generation.dart          # 项目生成协调器（搜索→评估→确认→规划→校验→保存）
│   ├── project_generation_controller.dart # 项目生成状态控制器
│   ├── daily_planning_policy.dart       # 日计划业务规则（滚动窗口、月卡推进、周期计数）
│   ├── schedule_load_service.dart        # 日程负载评估与重排建议生成
│   ├── user_model_service.dart          # USER_MODEL.md 兼容读写 / 统计 / 导出
│   ├── signal_service.dart              # 信号采集 / 编辑区分 / 凝练还原保护
│   ├── snapshot_write_queue.dart        # 串行快照写入队列
│   ├── memory_service.dart              # 记忆引擎 — 结构化存储 / 证据链 / 提取管线 / 建议偏好学习
│   ├── memory_extraction.dart           # AI 记忆提取 — 识别长期偏好/目标/约束 + 当前进度/困难/短期限制
│   ├── model_router.dart                # 模型路由器 — 能力接口抽象 + 度量采集
│   ├── model_router_metrics.dart        # 路由诊断指标持久化
│   ├── model_package_manager.dart       # 本地模型包下载/校验管理
│   ├── local_embedding_runtime.dart     # 端侧嵌入模型运行时
│   ├── local_embedding_service.dart     # 嵌入服务封装
│   ├── embedding_indexer.dart           # 文档嵌入索引器
│   ├── hybrid_retriever.dart            # 混合检索器（语义 + 关键词 + 来源 + 时间衰减）
│   ├── local_retrieval_coordinator.dart # 本地检索协调器
│   ├── local_retrieval_service.dart     # 本地检索服务
│   ├── study_timer_service.dart          # 学习计时服务 — timer/alarm 双模式 + 生命周期对账
│   ├── system_reminder_service.dart       # 系统提醒服务 — 后台/锁屏通知 + 精确闹钟调度
│   ├── foreground_reminder_service.dart   # 前台提醒服务 — 应用内计时/闹钟到期浮层通知
│   ├── timer_controller.dart             # 计时器状态控制器（ChangeNotifier）
│   ├── local_text_generation_coordinator.dart # 端侧文本生成协调器
│   ├── local_text_generation_runtime.dart     # 端侧文本生成运行时
│   ├── local_text_model_package.dart          # 端侧文本模型包管理
│   ├── local_structured_generation.dart       # 端侧结构化生成
│   ├── local_speech_model_package.dart          # 端侧语音模型包管理
│   ├── local_speech_recognition_coordinator.dart # 端侧语音识别协调器
│   ├── local_speech_recognition_runtime.dart     # 端侧语音识别运行时
│   ├── app_update_service.dart            # 应用更新检测（版本比对/APK 下载校验）
│   ├── today_suggestion_mapper.dart       # 今日建议映射（记忆→问候语建议）
│   ├── milestone_service.dart              # 学习里程碑存储与记忆关联
│   ├── daily_reflection.dart               # 每日复盘持久化与生成协调
│   └── secure_settings_store.dart       # Keychain 安全存储
├── widgets/
│   ├── score_bar.dart                   # 评估分数条
│   └── verdict_badge.dart               # 评估结论徽章
├── features/
│   ├── home/                            # 首页、侧边抽屉、设置面板、建议条
│   │   ├── home_page.dart
│   │   ├── side_drawer.dart
│   │   ├── settings_panel.dart
│   │   ├── suggestion_strip.dart
│   │   └── daily_reflection_card.dart
│   ├── chat/                            # 对话气泡、输入栏（对话 / 事项双模式）
│   │   ├── chat_bubble.dart
│   │   └── chat_input.dart
│   ├── todos/                           # 事项 Chip 轮播、编辑面板、拆分确认
│   │   ├── todo_chip_carousel.dart
│   │   ├── todo_edit_sheet.dart
│   │   └── split_confirm_sheet.dart
│   ├── calendar/                        # 日期条、月历、月视图
│   │   ├── date_strip.dart
│   │   ├── month_calendar.dart
│   │   └── month_view_sheet.dart
│   ├── projects/                        # 项目筛选栏、月卡翻页、编辑器、生成管线页
│   │   ├── project_tabs.dart
│   │   ├── month_card_pager.dart
│   │   ├── project_editor_page.dart
│   │   └── project_generation_page.dart
│   ├── settings/                        # 设置、用户模型编辑器、信号日志、本地智能、路由诊断
│   │   ├── settings_body.dart
│   │   ├── user_model_editor_page.dart
│   │   ├── signal_log_page.dart
│   │   ├── local_retrieval_page.dart       # 本地智能（检索与文本生成）
│   │   ├── model_router_metrics_page.dart
│   │   ├── memory_extraction_diagnostics_page.dart
│   │   ├── app_update_page.dart
│   │   └── user_hypotheses_page.dart
│   ├── memory/                          # 记忆管理中心、用户模型
│   │   ├── memory_center_page.dart
│   │   └── user_model_page.dart
│   ├── tools/                           # AI 工具浏览页
│   │   └── tools_page.dart
│   └── shared/                          # 拖拽把手
│       └── drag_handle.dart
├── android/.../EmbeddingEngine.kt       # Android 端侧嵌入引擎
├── test/                                # 测试套件（25 个文件）
├── tools/                               # 开发工具脚本
└── docs/                                # 技术文档
```

## License

MIT

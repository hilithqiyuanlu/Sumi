# Sumi（米糖）

一个**本地优先的 AI 自学助手**，帮你管理事项、追踪学习项目，结合 LLM 智能拆分与润色。

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2013%2B-lightgrey" alt="platform">
  <img src="https://img.shields.io/badge/framework-Flutter-02569B?logo=flutter" alt="flutter">
  <img src="https://img.shields.io/badge/API-DeepSeek-4B6BFB" alt="deepseek">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="license">
</p>

## 功能

- **📋 Keep 风格事项网格** — Masonry 瀑布流布局，Pin 置顶、长按拖拽排序
- **📅 日历导航** — 折叠态日期条 + 展开月视图，拖拽 todo 到日期分配
- **📂 项目系统** — 最多 3 个学习项目，月卡/解锁机制追踪进度
- **🤖 AI 智能拆分** — 输入 >16 字长文本自动调用 DeepSeek 拆分为多条
- **✨ AI 标题润色** — 点击润色按钮，AI 帮你凝练 todo 标题
- **🔐 本地优先** — 数据存本地快照，API Key 走安全存储，无需服务器

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.x |
| 语言 | Dart |
| 状态管理 | ChangeNotifier + InheritedNotifier |
| 存储 | JSON Snapshot + Secure Storage |
| AI 接口 | DeepSeek Chat API（流式 / 非流式） |
| 搜索 | Tavily Search API |

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

> **注意**：首次运行需要在「设置」Tab 中配置 [DeepSeek API Key](https://platform.deepseek.com/)，否则 AI 功能不可用。

## 项目结构

```
lib/
├── main.dart                         # 入口，初始化 store
├── main_shell.dart                   # 底部 Tab 导航
├── sumi_scope.dart                   # InheritedNotifier 注入
├── models/models.dart                # 数据模型
├── store/                            # 状态管理（ChangeNotifier）
├── data/                             # 本地持久化 + 快照
├── services/                         # DeepSeek AI / Tavily 服务
├── theme/                            # 主题配置
├── utils/                            # 工具函数
└── features/
    ├── todos/                        # 事项网格、输入、编辑面板
    ├── calendar/                     # 日期条、月历、月视图
    ├── projects/                     # 项目卡、月卡、编辑器
    └── settings/                     # API Key 配置、数据管理
```

## License

MIT

# AtlasDataProcessorPlus 项目介绍
这是一个用 Swift 开发的 macOS 测试数据监控与历史数据分析工具，支持实时监控测试平台数据采集、批量处理历史测试记录、智能屏蔽失败用例、多维度数据筛选与导出等功能，帮助快速定位和分析测试问题。

## 项目结构
```
AtlasDataProcessorPlus/
├── AtlasDataProcessorPlus/           # 主应用代码
│   ├── Controllers/                 # 控制器层
│   │   ├── MainWindowController.swift      # 主窗口控制器
│   │   ├── ChannelViewController.swift       # 监控主窗口通道视图控制器
│   │   ├── SummaryViewController.swift       # 监控主窗口汇总信息控制器
│   │   ├── SummaryDetailViewController.swift # 监控主窗口汇总详情矩阵控制器
│   │   ├── SummaryConfigPanelController.swift    # 监控主窗口配置面板
│   │   ├── TabbedToolWindowController.swift      # 监控汇总透明悬浮窗口
│   │   ├── TableConfigPopoverController.swift    # 表格配置弹出面板-透明悬浮窗口
│   │   ├── HistoryWindowController.swift         # 历史窗口控制器
│   │   ├── HistoryWindowController+Actions.swift # 历史窗口操作逻辑
│   │   ├── HistoryWindowController+Table.swift   # 历史窗口表格逻辑
│   │   ├── HistoryWindowController+UI.swift      # 历史窗口UI布局
│   │   ├── CurrentFailFilterController.swift     # 当前FAIL筛选控制器-历史窗口
│   │   ├── BlockFailPopoverController.swift      # 默认屏蔽项弹出面板-历史窗口
│   │   ├── DetailModalController.swift           # 详情弹窗控制器-历史窗口
│   │   └── NSVStackLayout.swift
│   ├── Models/                      # 数据模型层
│   │   ├── Channel.swift
│   │   ├── TestData.swift
│   │   ├── AtlasDataProcessor.swift
│   │   └── AppConfig.swift                        # 应用配置管理
│   ├── Managers/                    # 管理器层
│   │   └── MonitorManager.swift                  # 监控管理器
│   ├── Services/                    # 服务层
│   │   └── DataReaderService.swift
│   ├── AppDelegate.swift           # 应用代理
│   ├── main.swift                   # 入口文件
│   └── ViewController.swift
├── AtlasDataProcessorPlusTests/     # 单元测试
```

## 核心功能
1. 实时数据监控
   - 监控指定路径下的测试数据文件（ /Users/gdlocal/Library/Logs/Atlas/active ）
   - 每10ms检查一次文件变化，确保数据实时性
   - 每5秒扫描一次新通道
  
2. 多通道管理
   - 支持同时监控多个测试通道（格式： group-slot ）
   - 自动发现新通道并创建对应的监控视图
   - 使用标签页（TabView）展示不同通道的详细数据 

3. 数据可视化
   - **汇总信息视图** ：显示所有通道的统计信息（PASS/FAIL/总数）
   - **汇总详情视图** ：以测试项为行、通道为列的矩阵，横向对比同一轮测试各通道的测试值
   - **通道详情视图** ：每个通道的详细测试数据表格
   - 支持状态颜色标识（PASS绿色、FAIL红色）
   - **两种汇总模式互斥** ：同一时间只显示其一
     - 汇总信息模式：左侧汇总信息（可隐藏）+ 右侧通道详情
     - 汇总详情模式：矩阵覆盖整个主体区域，完全替代汇总信息与通道详情

4. 屏蔽功能
   - **当前fail筛选**：通过当前fail筛选按钮管理，显示当前所有失败用例列表（排除默认屏蔽项），按失败次数降序排列，通过勾选框快速筛选，设置保存到会话屏蔽列表。支持导出CSV文件，按通道号分组显示失败次数，方便分析不同通道的失败情况
   - **默认屏蔽项**：通过默认屏蔽项按钮管理，设置会持久保存到配置文件
   - **会话屏蔽**：通过右键菜单临时屏蔽，仅在当前会话有效
   - **智能过滤**：自动过滤被屏蔽的失败用例，提高数据分析效率
  
## 模块功能详解 
### Models 层
Channel.swift - 通道数据模型

   - 存储通道信息（group、slot、状态、统计数据）
   - 管理测试数据数组，支持最大行数限制
   - 提供PASS/FAIL计数功能
   - 通道状态：等待、运行中、测试结束、已停止

TestData.swift - 测试数据模型
   - 解析CSV格式的测试数据
   - 包含：测试名称、上下限、测量值、单位、状态等字段

AtlasDataProcessor.swift - 数据处理核心
   - 批量处理历史测试数据文件
   - 支持CSV格式数据解析和转换
   - 生成汇总统计信息和失败记录
   - 导出数据为CSV和JSON格式
   - 提供异步处理接口，适合UI应用

Services 层

DataReaderService.swift - 数据读取服务
   - 使用后台线程定时监控文件变化
   - 维护文件读取位置，避免重复读取
   - 自动检测新通道和通道状态变化
   - 通过委托模式通知UI更新 

### Controllers 层
MainWindowController.swift - 主窗口控制器
   - 应用程序主界面管理
   - **可折叠控制面板**（默认折叠为 28px 标题条）：
     - 展开态：监控路径、最大行数、自动滚动、清除数据、隐藏汇总
     - 折叠后仍保留高频控件：只显示FAIL行复选框、打开历史数据处理按钮
     - 点击标题条（箭头/标题或空白处）切换，折叠状态持久化到 AppConfig
   - **汇总模式切换**（控制面板标题条上的 NSSegmentedControl，默认选中汇总详情）：
     - 汇总信息：左侧汇总信息（默认隐藏，可用"显示汇总"按钮展开）+ 右侧通道详情
     - 汇总详情：矩阵视图覆盖整个分割视图区域，完全替代汇总信息与通道详情
   - 启动后自动开始监控，状态栏显示监控状态

ChannelViewController.swift - 通道详情控制器
   - 显示单个通道的详细测试数据表格
   - 支持自动滚动、只显示FAIL行
   - 右键菜单：复制、导出到Excel
   - 根据状态设置行背景色（FAIL行红色高亮）

SummaryViewController.swift - 汇总信息控制器
   - 显示所有通道的统计汇总
   - 双击通道名称可跳转到详细视图
   - 实时更新各通道的PASS/FAIL统计
   - 与汇总详情控制器互斥，同一时间只显示其一

SummaryDetailViewController.swift - 汇总详情控制器（矩阵视图）
   - **矩阵表格**：行 = 测试项，列 = 测试项 / Unit / 上限 / 下限 / 各通道（group-slot）
   - 固定列 Unit、上限、下限每行只显示一次（同一轮测试各通道 limit 相同）
   - 单元格显示对应通道该测试项的测量值，FAIL 单元格显示红色加粗文字
   - 测试项行按首次出现顺序排列，通道列按 group-slot 排序
   - **只显示FAIL**：与通道详情的"只显示FAIL行"复选框共用同一开关，勾选后仅保留存在 FAIL 的测试项行（默认勾选）
   - **只展示新一轮数据**：任一通道开始新一轮测试时整体清空重建，仅保留参与本轮的 running 通道；上一轮有、本轮未参与的已结束通道不会残留
   - **技术实现**：仅在新测试项/新通道出现时重建行列，其余情况局部刷新行，适配 10ms 轮询

HistoryWindowController.swift - 历史数据处理控制器
   - **打开即自动处理**：窗口打开时自动加载默认路径数据，无需手动点击
   - **扁平化表格展示**：
     - 所有记录在单一表格中展示，列包括序号、测试时间、SN、SlotID、S_BUILD、Status、测试项、测试值、上限值、下限值
     - FAIL 行的测试项/测试值用红色高亮显示
     - 每条 FAIL 记录只显示第一个未屏蔽的失败测试项，屏蔽一个后自动切换下一个
     - PASS 行的测试项/测试值列为空
   - **左侧筛选面板**：
     - 状态过滤：全部 / 仅 PASS / 仅 FAIL，下方实时显示统计行（总数 | PASS数 | FAIL数）
     - 数据目录选择与处理
     - 清除所有过滤
   - **工具栏**：
     - 排序：按 SLOT / 按 SN / 按时间 / 还原排序（按原始行号）
     - 搜索框：支持搜索 SN / S_BUILD / 测试项（支持 Cmd+C/V）
     - 重新解析、已屏蔽fail项管理、导出 CSV
   - **右键菜单**：
     - 查看详情：弹出详情窗口，三标签页展示（基本信息 / 全部项目 / 仅Fail），测试项竖排显示避免卡顿
     - 打开 Log 文件夹、复制 SN、复制测试项
     - 全局屏蔽该 Fail 项：屏蔽当前显示的单个 fail 测试项，添加到会话屏蔽列表
   - **屏蔽机制**：
     - 默认屏蔽项（AppConfig 持久化）：优先级最高，需手动添加
     - 会话屏蔽（当前fail筛选弹窗 + 右键菜单）：当前会话有效
     - 屏蔽后 FAIL 状态变为 PASS，数据行保留在表格中，统计行同步更新
   - **详情弹窗**：
     - 基本信息页：SN、时间、SlotID、S_BUILD、状态、Fail项数 + 内嵌测试项表格
     - 全部项目页：所有测试项竖排显示，PASS/FAIL 颜色标记，含测试值/上限/下限
     - 仅Fail页：仅显示失败测试项
     - 独立窗口模式，可按关闭按钮/Escape 正常退出
   - **技术实现**：
     - 使用 Extension 拆分代码：+Actions（业务逻辑）、+Table（表格代理）、+UI（布局）
     - 异步数据处理，确保 UI 响应性
     - CopyPasteSearchField 子类修复 Cmd+C/V 快捷键

```
// 历史数据处理窗口 UI 层级
NSWindow
└── NSView (containerView)
    ├── 工具栏 (toolbarView)
    │   └── NSStackView (水平)
    │       ├── 按 SLOT 排序按钮
    │       ├── 按 SN 排序按钮
    │       ├── 按时间排序按钮
    │       ├── 还原排序按钮
    │       ├── 分隔线
    │       ├── 重新解析按钮
    │       ├── 已屏蔽fail项按钮
    │       ├── 导出 CSV 按钮
    │       └── 搜索框 (CopyPasteSearchField)
    ├── 分隔线
    ├── 主体区域 (mainArea)
    │   ├── 侧栏 (sidebarView, 200px)
    │   │   └── NSScrollView
    │   │       └── NSStackView (垂直)
    │   │           ├── 数据目录标题
    │   │           ├── 路径输入框
    │   │           ├── 选择文件夹按钮
    │   │           ├── 开始处理按钮
    │   │           ├── 清除所有过滤按钮
    │   │           ├── 状态过滤标题
    │   │           ├── 全部 / 仅PASS / 仅FAIL 按钮组
    │   │           └── 统计行（共X条 | PASS:Y | FAIL:Z）
    │   ├── 侧栏分隔线
    │   └── 表格容器
    │       ├── NSScrollView
    │       │   └── ContextMenuTableView (支持右键)
    │       └── 列：序号 / 测试时间 / SN / SlotID / S_BUILD / Status / 测试项 / 测试值 / 上限值 / 下限值
    └── 状态栏 (statusLabel)

// 详情弹窗
NSWindow
└── NSTabView (三标签页)
    ├── 基本信息
    │   ├── 关键字段（SN、时间、SlotID、S_BUILD、状态、Fail项数）
    │   └── 内嵌 NSTableView（测试项 / 测试值 / 上限值 / 下限值 / 状态）
    ├── 全部项目
    │   └── NSScrollView → NSTableView（所有测试项竖排）
    └── 仅Fail
        └── NSScrollView → NSTableView（仅失败测试项竖排）
```
### 其他组件
NSVStackLayout.swift - 自定义垂直布局
   - 实现垂直堆叠布局容器
   - 支持间距和边距设置
   
AppDelegate.swift - 应用代理
   - 应用程序入口点
   - 管理主窗口和历史窗口
   - 处理应用生命周期事件

ViewController.swift - 基础视图控制器
   - 应用的基础视图控制器
   - 提供通用视图管理功能

## 使用说明
1. **实时监控模式**：
   - 启动应用后自动开始监控指定路径下的测试数据
   - **控制面板默认折叠**为标题条，点击标题条（箭头/标题或空白处）展开或折叠
   - 折叠状态下"只显示FAIL行"复选框与"打开历史数据处理"按钮仍可直接使用
   - 控制面板展开后可调整显示设置（最大行数、自动滚动、只显示FAIL）并显示/隐藏汇总
   - **汇总模式切换**：通过控制面板标题条上的"汇总信息 / 汇总详情"分段控件切换，默认选中汇总详情
     - **汇总信息**：左侧统计汇总（默认隐藏，点"显示汇总"展开）+ 右侧通道详情
     - **汇总详情**：以测试项为行、通道为列（含 Unit / 上限 / 下限）的矩阵，横向对比各通道测试值
   - "只显示FAIL行"默认勾选，同时作用于通道详情（只留 FAIL 行）与汇总详情（只留含 FAIL 的测试项行）
   - 通过"打开历史数据处理"按钮快速跳转历史窗口
   - 双击汇总信息中的通道名称快速跳转到对应通道

2. **历史数据处理**：
   - 通过菜单栏（Command+H）或主窗口按钮打开历史数据处理窗口
   - 窗口打开后自动加载默认路径并开始处理数据
   - 左侧面板可切换状态过滤（全部/仅PASS/仅FAIL），统计行实时更新
   - 排序：支持按 SLOT/SN/时间排序，点击"还原排序"恢复原始行号顺序
   - 搜索：在搜索框中输入 SN/S_BUILD/测试项 进行过滤（支持 Cmd+C/V）
   - 右键菜单功能：
     - **查看详情**：弹出三标签页详情窗口，测试项竖排显示，避免卡顿
     - **全局屏蔽该 Fail 项**：屏蔽当前显示的单个 fail 测试项（添加到会话屏蔽列表）
     - **复制 SN / 复制测试项**：快速复制到剪贴板
     - **打开 Log 文件夹**：打开记录对应的日志目录
   - 工具栏按钮：
     - **重新解析**：重新处理当前目录数据
     - **已屏蔽fail项**：打开弹窗管理会话屏蔽的 fail 项，支持勾选/取消
     - **导出 CSV**：导出当前过滤后的数据为 CSV 文件

## 功能亮点
1. **实时性**：10ms级别的数据更新，确保测试数据实时显示
2. **多通道**：支持同时监控多个测试通道，自动发现新通道
3. **可视化**：清晰的状态标识和数据展示
4. **灵活性**：可调整的显示设置和筛选排序功能
5. **易用性**：直观的用户界面和操作流程
6. **可扩展性**：模块化设计，易于添加新功能

## 技术架构
- **MVC模式**：清晰的分层设计，分离数据、视图和控制器
- **委托模式**：服务层通过委托通知UI更新
- **后台线程**：数据读取在后台执行，不阻塞UI
- **Auto Layout**：响应式UI布局，适应不同窗口大小
- **NSPopover**：现代的弹出式筛选界面
- **表格视图**：高效的数据展示和交互

## 系统要求
- macOS 10.15或更高版本
- Swift 5.0或更高版本
- Xcode 11.0或更高版本

## 图标参数
16x16 Dock 栏小图标 32x32 Dock 栏图标 128x128 Finder 图标 256x256 大图标 512x512 超大图标

## 总结
AtlasDataProcessorPlus 是一款基于 Swift 开发的 macOS 测试数据监控与历史分析工具，提供实时数据监控、多通道管理、智能屏蔽失败用例、历史数据批量处理与多维度分析等功能，帮助研发团队高效定位和解决测试问题。

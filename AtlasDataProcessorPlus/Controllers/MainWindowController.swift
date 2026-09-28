//
//  MainWindowController.swift
//  TestMonitorApp
//
//  Created by Your Name on 2026-01-29.
//

import Cocoa

class MainWindowController: NSWindowController, DataReaderServiceDelegate, NSSplitViewDelegate, NSTextFieldDelegate {
    
    private let basePath = URL(fileURLWithPath: "/Users/gdlocal/Library/Logs/Atlas/active")
    private var dataReaderService: DataReaderService!
    
    /// 通道数据（key: "group-slot"），供 MonitorManager 等外部访问
    var channels: [String: Channel] = [:]
    /// 按 group-slot 排序的通道名称列表
    private var sortedChannelNames: [String] = []
    /// 当前选中的通道名称
    private var currentChannelName: String?
    
    /// 唯一的通道详情视图控制器（所有通道共用）
    private var sharedChannelController: ChannelViewController!
    private var summaryViewController: SummaryViewController!
    /// 汇总详情矩阵视图控制器（与统计汇总互斥显示）
    private var summaryDetailViewController: SummaryDetailViewController!
    
    // UI 组件
    private var splitView: NSSplitView!
    private var channelSelector: NSSegmentedControl!
    private var controlView: NSView!
    private var pathLabelTitle: NSTextField!
    private var pathLabel: NSTextField!
    private var openHistoryButton: NSButton!
    private var maxRowsLabel: NSTextField!
    private var maxRowsTextField: NSTextField!
    private var maxRowsStepper: NSStepper!
    private var autoScrollCheckbox: NSButton!
    private var showFailOnlyCheckbox: NSButton!
    private var clearButton: NSButton!
    private var toggleSummaryButton: NSButton!
    private var statusBar: NSTextField!

    /// 控制面板标题条（折叠后仍保留）
    private var panelTitleBar: NSView!
    /// 控制面板内容区（折叠时隐藏）
    private var panelContentContainer: NSView!
    /// 折叠/展开指示按钮（chevron）
    private var disclosureButton: NSButton!
    /// 控制面板高度约束（折叠动画时修改其 constant）
    private var controlViewHeightConstraint: NSLayoutConstraint!
    /// chevron 图像（macOS 11+ 使用 SF Symbols，低版本回退字符）
    private var disclosureDownImage: NSImage?
    private var disclosureRightImage: NSImage?

    /// 控制面板展开高度（标题条 28 + 两行控件 52）
    private let panelExpandedHeight: CGFloat = 80
    /// 控制面板折叠后高度（仅标题条）
    private let panelTitleBarHeight: CGFloat = 28

    // 配置
    private var maxRows: Int = AppConfig.shared.channelMaxRows {
        didSet {
            AppConfig.shared.channelMaxRows = maxRows
        }
    }
    private var autoScroll: Bool = true
    private var showFailOnly: Bool = true
    private var isSummaryVisible: Bool = true
    /// 控制面板是否折叠（从配置恢复）
    private var isPanelCollapsed: Bool = AppConfig.shared.controlPanelCollapsed
    /// 汇总显示模式：统计 / 详情（默认详情）
    private enum SummaryMode { case stats, detail }
    private var summaryMode: SummaryMode = .detail
    /// 控制面板标题条上的汇总模式切换控件
    private var summaryModeSegmented: NSSegmentedControl!
    
    // ✅ 添加无参数初始化方法
    convenience init() {
        // 创建窗口（尺寸按屏幕钳制，兼容工厂小屏显示器）
        let preferredSize = AtlasUtils.clampedWindowSize(preferred: NSSize(width: 1210, height: 450))
        let contentRect = NSRect(x: 0, y: 400, width: preferredSize.width, height: preferredSize.height)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "测试平台数据监控工具"
        
        self.init(window: window)
        
        // 设置窗口代理
        window.delegate = self
        
        // 初始化 UI
        setupUI()
        setupDataReaderService()
        
        // 启动状态更新定时器
        Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateStatus), userInfo: nil, repeats: true)

    }
    
    // ✅ 正确的指定初始化方法
    override init(window: NSWindow?) {
        super.init(window: window)
        print("🎯 MainWindowController.init(window:) 被调用")
        
        // 注意：这里不要重新创建 window！
        // 使用传入的 window 或已在 convenience init 中创建的 window
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        print("✅ MainWindowController.windowDidLoad() - 窗口已加载")
        // 注意：此方法不会被调用，因为窗口是通过代码手动创建的
        // 如果将来改用 Xib/Storyboard 加载窗口，此方法会被自动调用
        // 目前监控已在 convenience init() 中手动启动

        // 确保窗口设置正确
        if let window = window {
            print("🪟 窗口标题: \(window.title)")
            print("📏 窗口尺寸: \(window.frame)")
        }
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        print("👁️ MainWindowController.showWindow() 被调用")
        
        // 确保窗口显示在最前
        window?.makeKeyAndOrderFront(sender)

        // 手动启动监控（因为 windowDidLoad() 不会在代码创建窗口时被调用）
        startMonitoring()

        // 延迟设置分割比例，确保视图布局完成后再设置
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.applySummaryVisibility()
    }

    }
    
    private func setupUI() {
        print("🛠️ 开始设置UI")
        // 获取窗口的内容视图容器
        let contentView = window!.contentView!
        // 启用图层支持，允许设置背景色
        contentView.wantsLayer = true
        // 设置窗口背景（跟随系统明暗模式）
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // 控制面板
        // 调用子方法创建控制面板（包含所有按钮、输入框等）
        setupControlView()
        // 关键！ 禁用自动调整大小，启用 Auto Layout
        controlView.translatesAutoresizingMaskIntoConstraints = false
        // - 将控制面板添加到内容视图
        contentView.addSubview(controlView)
        
        // 分割视图
        // 创建分割视图容器
        splitView = NSSplitView()
        // isVertical = false ： 水平分割 （上下布局）， true 则为左右分割
        splitView.isVertical = true 
        // 分隔条样式为细线
        splitView.dividerStyle = .thin
        // 启用 Auto Layout
        splitView.translatesAutoresizingMaskIntoConstraints = false
        // 添加到内容视图
        contentView.addSubview(splitView)
        
        // 左侧：汇总信息容器（状态一：统计汇总[可隐藏] + 右侧通道详情）
        let summaryView = NSView()
        summaryViewController = SummaryViewController()
        summaryViewController.mainWindowController = self
        summaryView.addSubview(summaryViewController.view)
        summaryViewController.view.frame = summaryView.bounds
        summaryViewController.view.autoresizingMask = [.width, .height]
        // 将容器添加到分割视图
        splitView.addSubview(summaryView)

        // 汇总详情矩阵（状态二：覆盖整个分割视图区域，完全替代汇总信息与通道详情）
        summaryDetailViewController = SummaryDetailViewController()
        summaryDetailViewController.mainWindowController = self
        summaryDetailViewController.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(summaryDetailViewController.view, positioned: .above, relativeTo: splitView)
        // 视图已加载，同步初始过滤状态（默认勾选"只显示FAIL行"）
        summaryDetailViewController.showFailOnly = showFailOnly
        NSLayoutConstraint.activate([
            summaryDetailViewController.view.topAnchor.constraint(equalTo: splitView.topAnchor),
            summaryDetailViewController.view.leadingAnchor.constraint(equalTo: splitView.leadingAnchor),
            summaryDetailViewController.view.trailingAnchor.constraint(equalTo: splitView.trailingAnchor),
            summaryDetailViewController.view.bottomAnchor.constraint(equalTo: splitView.bottomAnchor),
        ])
        
        // 右侧：通道详情区域（通道选择器 + 共享表格）
        let rightView = NSView()
        rightView.wantsLayer = true
        rightView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // 通道选择器 - 顶部显示所有通道标签
        channelSelector = NSSegmentedControl()
        channelSelector.segmentStyle = .texturedSquare
        channelSelector.trackingMode = .selectOne
        channelSelector.target = self
        channelSelector.action = #selector(channelSelected(_:))
        channelSelector.setAccessibilityLabel("通道选择器")
        channelSelector.translatesAutoresizingMaskIntoConstraints = false
        rightView.addSubview(channelSelector)
        
        // 共享通道视图（所有通道共用此视图）
        // 使用一个空的占位 channel 初始化，后续有新通道时切换
        let placeholderChannel = Channel(group: "--", slot: "--")
        sharedChannelController = ChannelViewController(channel: placeholderChannel)
        sharedChannelController.mainWindowController = self
        sharedChannelController.view.translatesAutoresizingMaskIntoConstraints = false
        rightView.addSubview(sharedChannelController.view)
        
        // 通道选择器 + 表格布局
        NSLayoutConstraint.activate([
            channelSelector.topAnchor.constraint(equalTo: rightView.topAnchor, constant: 4),
            channelSelector.leadingAnchor.constraint(equalTo: rightView.leadingAnchor, constant: 8),
            channelSelector.trailingAnchor.constraint(lessThanOrEqualTo: rightView.trailingAnchor, constant: -8),
            
            sharedChannelController.view.topAnchor.constraint(equalTo: channelSelector.bottomAnchor, constant: 4),
            sharedChannelController.view.leadingAnchor.constraint(equalTo: rightView.leadingAnchor),
            sharedChannelController.view.trailingAnchor.constraint(equalTo: rightView.trailingAnchor),
            sharedChannelController.view.bottomAnchor.constraint(equalTo: rightView.bottomAnchor)
        ])
        
        splitView.addSubview(rightView)
        
        // 设置分割视图代理
        splitView.delegate = self
        
        // 状态栏
        statusBar = NSTextField(labelWithString: "监控已启动，正在扫描通道...")
        statusBar.alignment = .left
        statusBar.isEditable = false
        statusBar.isSelectable = false
        statusBar.font = NSFont.systemFont(ofSize: 12)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusBar)
        
        // 控制面板高度约束（折叠/展开时动态修改）
        controlViewHeightConstraint = controlView.heightAnchor.constraint(
            equalToConstant: isPanelCollapsed ? panelTitleBarHeight : panelExpandedHeight
        )
        controlViewHeightConstraint.isActive = true

        // 设置布局约束
        NSLayoutConstraint.activate([
            // 控制面板约束
            controlView.topAnchor.constraint(equalTo: contentView.topAnchor),
            controlView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controlView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            // 分割视图约束
            splitView.topAnchor.constraint(equalTo: controlView.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            // 状态栏约束
            statusBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 20)
        ])

        // 应用汇总面板初始可见状态（默认隐藏）与汇总模式初始状态（默认详情）
        applySummaryVisibility()
        applySummaryMode()
    }
    
    private func setupControlView() {
        print("🔧 setupControlView() 开始")

        controlView = NSView()
        controlView.wantsLayer = true
        // 折叠动画时裁剪溢出的内容区，避免内容悬浮在表格上方
        controlView.layer?.masksToBounds = true
        controlView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor

        // 先创建所有视图组件
        createAllViews()

        // MARK: 标题条（折叠后仍然保留）
        let titleBar = NSView()
        titleBar.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(titleBar)
        panelTitleBar = titleBar

        // 标题条底部分隔线（先添加，位于最底层，不拦截点击）
        let titleDivider = NSBox()
        titleDivider.boxType = .separator
        titleDivider.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleDivider)

        // 整条标题条的点击区域（无边框按钮，位于内容之下），
        // 空白区域点击可折叠/展开；上方的复选框、历史按钮优先响应
        let titleClickButton = NSButton(title: "", target: self, action: #selector(toggleControlPanel))
        titleClickButton.isBordered = false
        titleClickButton.setButtonType(.momentaryChange)
        titleClickButton.translatesAutoresizingMaskIntoConstraints = false
        titleClickButton.setAccessibilityLabel("折叠或展开控制面板")
        titleBar.addSubview(titleClickButton)

        // 折叠指示箭头
        disclosureButton = makeDisclosureButton()

        // 标题文字本身也可点击折叠
        let titleTextButton = NSButton()
        titleTextButton.isBordered = false
        titleTextButton.target = self
        titleTextButton.action = #selector(toggleControlPanel)
        titleTextButton.translatesAutoresizingMaskIntoConstraints = false
        titleTextButton.attributedTitle = NSAttributedString(
            string: "控制面板",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        // 弹性间距，把高频操作推到右侧（点击穿透到标题条按钮）
        let spacer = ClickThroughView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 标题行：箭头 + 标题 + 汇总模式切换 ......... 只显示FAIL行 + 打开历史数据处理（折叠后仍可见）
        let titleStack = ClickThroughStackView(views: [
            disclosureButton, titleTextButton, summaryModeSegmented!, spacer,
            showFailOnlyCheckbox!, openHistoryButton!
        ])
        titleStack.orientation = .horizontal
        titleStack.spacing = 8
        titleStack.alignment = .centerY
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(titleStack)

        // MARK: 内容区（折叠时隐藏）
        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        controlView.addSubview(contentContainer)
        panelContentContainer = contentContainer

        // 两行弹性布局（小屏/大屏通用，NSStackView 自动处理压缩）：
        // 行 1：监控路径
        // 行 2：最大行数 + 复选框 + 操作按钮
        let row1 = NSStackView(views: [pathLabelTitle, pathLabel])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.alignment = .centerY

        let row2 = NSStackView(views: [
            maxRowsLabel!, maxRowsTextField!, maxRowsStepper!,
            autoScrollCheckbox!,
            clearButton!, toggleSummaryButton!
        ])
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.alignment = .centerY

        let rows = NSStackView(views: [row1, row2])
        rows.orientation = .vertical
        rows.spacing = 4
        rows.alignment = .leading
        rows.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(rows)

        NSLayoutConstraint.activate([
            // 标题条
            titleBar.topAnchor.constraint(equalTo: controlView.topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: controlView.leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: controlView.trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: panelTitleBarHeight),

            // 分隔线贴标题条底部
            titleDivider.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor),
            titleDivider.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor),
            titleDivider.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor),
            titleDivider.heightAnchor.constraint(equalToConstant: 1),

            // 整行点击区域铺满标题条
            titleClickButton.topAnchor.constraint(equalTo: titleBar.topAnchor),
            titleClickButton.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor),
            titleClickButton.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor),
            titleClickButton.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor),

            // 标题行内容
            titleStack.topAnchor.constraint(equalTo: titleBar.topAnchor),
            titleStack.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor, constant: 8),
            titleStack.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor, constant: -8),
            titleStack.bottomAnchor.constraint(equalTo: titleBar.bottomAnchor),

            // 内容区：标题条下方铺满剩余高度
            contentContainer.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: controlView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: controlView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: controlView.bottomAnchor),

            // 两行控件
            rows.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 8),
            rows.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor, constant: -8),
            rows.topAnchor.constraint(greaterThanOrEqualTo: contentContainer.topAnchor, constant: 2),
            rows.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor, constant: -2),
            rows.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
        ])

        // 应用初始折叠状态（无动画）
        panelContentContainer.isHidden = isPanelCollapsed
        updateDisclosureIndicator()

        print("✅ setupControlView() 完成")
    }

    /// 创建折叠/展开指示按钮（macOS 11+ 使用 SF Symbols，低版本回退字符）
    private func makeDisclosureButton() -> NSButton {
        let button: NSButton
        if #available(macOS 11.0, *) {
            disclosureDownImage = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "展开控制面板")
            disclosureRightImage = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "折叠控制面板")
            if let downImage = disclosureDownImage {
                button = NSButton(image: downImage, target: self, action: #selector(toggleControlPanel))
                button.contentTintColor = NSColor.labelColor
            } else {
                button = NSButton(title: "▼", target: self, action: #selector(toggleControlPanel))
            }
        } else {
            button = NSButton(title: "▼", target: self, action: #selector(toggleControlPanel))
        }
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel("折叠或展开控制面板")
        return button
    }

    /// 根据当前折叠状态更新箭头图标/字符
    private func updateDisclosureIndicator() {
        if #available(macOS 11.0, *), disclosureDownImage != nil {
            disclosureButton.image = isPanelCollapsed ? disclosureRightImage : disclosureDownImage
        } else {
            disclosureButton.title = isPanelCollapsed ? "▶" : "▼"
        }
    }

    /// 折叠/展开控制面板：切换高度约束并做平滑动画，状态持久化到配置文件
    @objc private func toggleControlPanel() {
        isPanelCollapsed.toggle()
        AppConfig.shared.controlPanelCollapsed = isPanelCollapsed
        AppConfig.shared.saveConfigToFile()
        updateDisclosureIndicator()

        if isPanelCollapsed {
            // 折叠：内容淡出 + 高度收缩到标题条，动画结束后隐藏内容
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                self.panelContentContainer.animator().alphaValue = 0
                self.controlViewHeightConstraint.animator().constant = self.panelTitleBarHeight
                self.controlView.layoutSubtreeIfNeeded()
            }, completionHandler: {
                self.panelContentContainer.isHidden = true
                self.panelContentContainer.alphaValue = 1
            })
        } else {
            // 展开：先显示内容，再淡入 + 高度恢复
            panelContentContainer.isHidden = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                self.panelContentContainer.animator().alphaValue = 1
                self.controlViewHeightConstraint.animator().constant = self.panelExpandedHeight
                self.controlView.layoutSubtreeIfNeeded()
            }
        }
    }

    private func createAllViews() {
        print("  ↪️ 创建所有视图组件")

        // 路径显示
        pathLabelTitle = NSTextField(labelWithString: "监控路径:")
        pathLabelTitle.font = NSFont.systemFont(ofSize: 12)
        pathLabelTitle.translatesAutoresizingMaskIntoConstraints = false

        pathLabel = NSTextField(string: basePath.path)
        pathLabel.isEditable = false
        pathLabel.isSelectable = true
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.backgroundColor = NSColor.controlBackgroundColor
        pathLabel.isBordered = true
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false

        // 打开历史数据处理
        openHistoryButton = NSButton(title: "打开历史数据处理", target: nil, action: nil)
        openHistoryButton.bezelStyle = .rounded
        openHistoryButton.font = NSFont.systemFont(ofSize: 12)
        openHistoryButton.translatesAutoresizingMaskIntoConstraints = false
        openHistoryButton.target = NSApp.delegate
        openHistoryButton.action = #selector(AppDelegate.showHistoryWindow(_:))

        // 显示设置
        maxRowsLabel = NSTextField(labelWithString: "最大行数:")
        maxRowsLabel.font = NSFont.systemFont(ofSize: 12)
        maxRowsLabel.translatesAutoresizingMaskIntoConstraints = false

        maxRowsTextField = NSTextField(string: "\(maxRows)")
        maxRowsTextField.isEditable = true
        maxRowsTextField.isSelectable = true
        maxRowsTextField.font = NSFont.systemFont(ofSize: 12)
        maxRowsTextField.backgroundColor = NSColor.textBackgroundColor
        maxRowsTextField.isBordered = true
        maxRowsTextField.alignment = .center
        maxRowsTextField.translatesAutoresizingMaskIntoConstraints = false
        maxRowsTextField.delegate = self

        maxRowsStepper = NSStepper()
        maxRowsStepper.minValue = 100
        maxRowsStepper.maxValue = 10000
        maxRowsStepper.increment = 100
        maxRowsStepper.intValue = Int32(maxRows)
        maxRowsStepper.target = self
        maxRowsStepper.action = #selector(maxRowsChanged)
        maxRowsStepper.translatesAutoresizingMaskIntoConstraints = false

        autoScrollCheckbox = NSButton(checkboxWithTitle: "自动滚动", target: self, action: #selector(autoScrollChanged))
        autoScrollCheckbox.state = .on
        autoScrollCheckbox.translatesAutoresizingMaskIntoConstraints = false

        showFailOnlyCheckbox = NSButton(checkboxWithTitle: "只显示FAIL行", target: self, action: #selector(showFailOnlyChanged))
        showFailOnlyCheckbox.state = .on
        showFailOnlyCheckbox.translatesAutoresizingMaskIntoConstraints = false

        clearButton = NSButton(title: "清除所有数据", target: self, action: #selector(clearAllData))
        clearButton.bezelStyle = .rounded
        clearButton.font = NSFont.systemFont(ofSize: 12)
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        toggleSummaryButton = NSButton(title: "隐藏汇总", target: self, action: #selector(toggleSummaryVisibility))
        toggleSummaryButton.bezelStyle = .rounded
        toggleSummaryButton.font = NSFont.systemFont(ofSize: 12)
        toggleSummaryButton.translatesAutoresizingMaskIntoConstraints = false

        // 汇总模式切换（统计汇总 / 汇总详情），放在控制面板标题条
        summaryModeSegmented = NSSegmentedControl(
            labels: ["汇总信息", "汇总详情"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(summaryModeChanged(_:))
        )
        summaryModeSegmented.selectedSegment = (summaryMode == .detail) ? 1 : 0
        summaryModeSegmented.font = NSFont.systemFont(ofSize: 11)
        summaryModeSegmented.translatesAutoresizingMaskIntoConstraints = false
        summaryModeSegmented.setAccessibilityLabel("切换汇总显示模式")

        // 固定宽度项：路径框 300（超宽时截断显示头部），行数输入框 60
        pathLabel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        maxRowsTextField.widthAnchor.constraint(equalToConstant: 60).isActive = true

        // 无障碍标签（VoiceOver 可读）
        pathLabel.setAccessibilityLabel("监控路径")
        openHistoryButton.setAccessibilityLabel("打开历史数据处理窗口")
        maxRowsTextField.setAccessibilityLabel("通道最大显示行数")
        maxRowsStepper.setAccessibilityLabel("调整最大行数")
        clearButton.setAccessibilityLabel("清除所有通道数据")
        toggleSummaryButton.setAccessibilityLabel("显示或隐藏汇总面板")
    }

    private func setupDataReaderService() {
        dataReaderService = DataReaderService(basePath: basePath)
        dataReaderService.delegate = self
    }
    
    @objc private func startMonitoring() {
        dataReaderService.start()
        statusBar.stringValue = "监控已启动"
    }
    
    @objc public func stopMonitoring() {
        dataReaderService.stop()
        
        // 更新所有通道状态
        for (_, channel) in channels {
            channel.status = .stopped
            summaryViewController.updateChannelStats(channel)
            summaryDetailViewController.updateChannelStats(channel)
        }
        
        statusBar.stringValue = "监控已停止"
    }
    
    @objc private func maxRowsChanged() {
        maxRows = Int(maxRowsStepper.intValue)
        maxRowsTextField.stringValue = "\(maxRows)"
        
        for (_, channel) in channels {
            channel.maxRows = maxRows
        }
    }
    
    // MARK: - NSTextFieldDelegate
    
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField, textField === maxRowsTextField else {
            return
        }
        
        if let value = Int(textField.stringValue), value >= 100 && value <= 10000 {
            maxRows = value
            maxRowsStepper.intValue = Int32(maxRows)
            
            for (_, channel) in channels {
                channel.maxRows = maxRows
            }
        } else {
            // 恢复为有效范围的值
            maxRowsTextField.stringValue = "\(maxRows)"
        }
    }
    
    @objc private func autoScrollChanged() {
        autoScroll = autoScrollCheckbox.state == .on
        sharedChannelController.autoScroll = autoScroll
        statusBar.stringValue = autoScroll ? "已启用自动滚动模式" : "已禁用自动滚动模式"
    }
    
    @objc private func showFailOnlyChanged() {
        showFailOnly = showFailOnlyCheckbox.state == .on
        sharedChannelController.showFailOnly = showFailOnly
        sharedChannelController.updateTable()
        // 同步控制汇总详情矩阵（只显示存在FAIL的测试项行）
        summaryDetailViewController.showFailOnly = showFailOnly
        statusBar.stringValue = showFailOnly ? "已启用只显示FAIL行模式" : "已启用显示所有行模式"
    }
    
    @objc private func clearAllData() {
        for (_, channel) in channels {
            channel.clearData()
        }
        sharedChannelController.updateTable()
        summaryViewController.clearAll()
        summaryDetailViewController.clearAll()
        statusBar.stringValue = "所有数据已清除"
    }
    
    @objc private func toggleSummaryVisibility() {
        isSummaryVisible = !isSummaryVisible
        applySummaryVisibility()
    }

    /// 根据 isSummaryVisible 状态应用汇总面板的显示/隐藏与按钮标题
    private func applySummaryVisibility() {
        guard let summaryView = splitView.subviews.first else { return }
        if isSummaryVisible {
            summaryView.isHidden = false
            toggleSummaryButton.title = "隐藏汇总"
            splitView.setPosition(220, ofDividerAt: 0)
        } else {
            summaryView.isHidden = true
            toggleSummaryButton.title = "显示汇总"
            splitView.setPosition(0, ofDividerAt: 0)
        }
    }

    /// 汇总模式切换：统计汇总 <-> 汇总详情（互斥显示）
    @objc private func summaryModeChanged(_ sender: NSSegmentedControl) {
        summaryMode = (sender.selectedSegment == 1) ? .detail : .stats
        applySummaryMode()
    }

    /// 根据 summaryMode 切换两种状态：
    /// 状态一（stats）：splitView 布局 = 汇总信息（可隐藏）+ 通道详情
    /// 状态二（detail）：仅显示汇总详情矩阵，完全替代汇总信息与通道详情
    private func applySummaryMode() {
        guard summaryViewController != nil, summaryDetailViewController != nil else { return }
        let isDetail = (summaryMode == .detail)
        summaryDetailViewController.view.isHidden = !isDetail
        splitView.isHidden = isDetail
        // "隐藏汇总"按钮仅在状态一有意义
        if toggleSummaryButton != nil {
            toggleSummaryButton.isEnabled = !isDetail
        }
        if !isDetail {
            applySummaryVisibility()
        }
    }

    @objc private func updateStatus() {
        let activeChannels = channels.count
        
        if dataReaderService != nil {
            var status = "监控中 | 活动通道: \(activeChannels)"
            if showFailOnly {
                status += " | 只显示FAIL行"
            }
            statusBar.stringValue = status
        } else {
            statusBar.stringValue = "监控停止 | 活动通道: \(activeChannels)"
        }
    }
    
    // MARK: - DataReaderServiceDelegate
    
    func dataReaderService(_ service: DataReaderService, didFindNewDataForChannel channel: Channel, data: [TestData]) {
        DispatchQueue.main.async {
            let key = channel.name
            
            // 如果是新通道，加入通道列表
            if !self.channels.keys.contains(key) {
                self.channels[key] = channel
                self.rebuildChannelSelector()
                
                // 如果是第一个通道，自动选中
                if self.currentChannelName == nil {
                    self.selectChannel(key)
                }
                
                self.statusBar.stringValue = "发现新通道: \(channel.name)"
            }
            
            // 如果是当前选中的通道，刷新表格
            if key == self.currentChannelName {
                self.sharedChannelController.updateTable()
            }
            
            // 更新汇总统计
            self.summaryViewController.updateChannelStats(channel)
            self.summaryDetailViewController.updateChannelStats(channel)
        }
    }
    
    func dataReaderService(_ service: DataReaderService, didUpdateChannelStatus channel: Channel, status: Channel.ChannelStatus) {
        DispatchQueue.main.async {
            // 更新汇总统计
            self.summaryViewController.updateChannelStats(channel)
            self.summaryDetailViewController.updateChannelStats(channel)
            
            if status == .ended {
                self.statusBar.stringValue = "通道 \(channel.name) 测试结束"
            }
        }
    }

    func dataReaderService(_ service: DataReaderService, didClearChannelData channel: Channel) {
        DispatchQueue.main.async {
            let key = channel.name
            self.summaryViewController.updateChannelStats(channel)
            // 汇总详情只展示新一轮数据：以当前 running 通道整体重建矩阵，
            // 上一轮有、本轮未参与的通道（ended）不再出现；单通道详情的历史保留不受影响
            let runningChannels = service.getChannels().filter { $0.status == .running }
            self.summaryDetailViewController.resetForNewRound(runningChannels: runningChannels)
            self.statusBar.stringValue = "通道 \(channel.name) 开始新一轮测试，数据已清空"
            
            // 如果清空的是当前选中的通道，刷新表格
            if key == self.currentChannelName {
                self.sharedChannelController.updateTable()
            }
        }
    }
    
    // MARK: - 通道选择

    @objc private func channelSelected(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard index >= 0, index < sortedChannelNames.count else { return }
        selectChannel(sortedChannelNames[index])
    }
    
    private func selectChannel(_ name: String) {
        guard let channel = channels[name], name != currentChannelName else { return }
        currentChannelName = name
        sharedChannelController.autoScroll = autoScroll
        sharedChannelController.showFailOnly = showFailOnly
        sharedChannelController.switchToChannel(channel)
        // 更新 segmented control 选中状态
        if let idx = sortedChannelNames.firstIndex(of: name) {
            channelSelector.selectedSegment = idx
        }
    }
    
    private func rebuildChannelSelector() {
        // 排序通道名称（统一使用共享排序实现）
        sortedChannelNames = AtlasUtils.sortedChannelNames(Array(channels.keys))
        
        channelSelector.segmentCount = sortedChannelNames.count
        for (i, name) in sortedChannelNames.enumerated() {
            channelSelector.setLabel(name, forSegment: i)
            channelSelector.setWidth(90, forSegment: i)
        }
        
        // 恢复选中状态
        if let current = currentChannelName, let idx = sortedChannelNames.firstIndex(of: current) {
            channelSelector.selectedSegment = idx
        } else if sortedChannelNames.count > 0 {
            channelSelector.selectedSegment = -1
        }
    }
    
    // MARK: - Public Methods
    
    func showChannelDetails(_ channel: Channel) {
        let key = channel.name
        // 如果通道不在列表中，先添加
        if channels[key] == nil {
            channels[key] = channel
            rebuildChannelSelector()
        }
        selectChannel(key)
    }

   // MARK: - NSSplitViewDelegate
    
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 限制左侧汇总区域的最大宽度为 220 像素
        if dividerIndex == 0 {
            return 220
        }
        return proposedMaximumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // 限制左侧汇总区域的最小宽度为 0 像素
        if dividerIndex == 0 {
            return 0
        }
        return proposedMinimumPosition
    }

    // MARK: - NSWindowDelegate
    
    func windowDidResize(_ notification: Notification) {
        // 窗口尺寸变化时，确保左侧宽度不超过最大限制
        let maxLeftWidth: CGFloat = 220
        let currentLeftWidth = splitView.subviews[0].frame.width
        
        if currentLeftWidth > maxLeftWidth {
            splitView.setPosition(maxLeftWidth, ofDividerAt: 0)
        }
    }

}
// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 不停止监控，允许后台继续运行
    }
}

// MARK: - 点击穿透辅助视图

/// 自身不响应鼠标点击的容器：空白区域的点击会穿透到下层视图，
/// 子视图（按钮、复选框等）仍可正常交互。
/// 用于控制面板标题条的弹性间距，使整条标题条空白处均可点击折叠。
private class ClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, let superview = superview else { return nil }
        // point 在父视图坐标系，先转换到自身坐标系再做判断
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(localPoint) {
                return hit
            }
        }
        return nil
    }
}

/// 点击穿透版 NSStackView：栈本身及其间距区域不拦截点击，
/// 仅栈内实际控件响应鼠标事件。
private class ClickThroughStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, let superview = superview else { return nil }
        // point 在父视图坐标系，先转换到自身坐标系再做判断
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        for subview in subviews.reversed() {
            if let hit = subview.hitTest(localPoint) {
                return hit
            }
        }
        return nil
    }
}

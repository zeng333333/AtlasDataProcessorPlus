//
//  SummaryDetailViewController.swift
//  TestMonitorApp
//
//  Created by Your Name on 2026-01-29.
//

import Cocoa

/// 汇总详情视图控制器：矩阵表格
/// 行 = 测试项（首列），固定列 = Unit / 上限 / 下限，其后每通道一列显示测试值
/// 同一次测试各通道的测试项与 limit 相同，故 limit 只在固定列展示一次
class SummaryDetailViewController: NSViewController {

    // MARK: - 属性

    weak var mainWindowController: MainWindowController?
    private var tableView: NSTableView!

    /// 通道数据源（列），按 sortKey 排序
    private var dataSource: [Channel] = []
    /// 去重且有序的测试项（行），按首次出现顺序
    private var allTestNames: [String] = []
    /// 已建列的通道名，用于检测通道增减并重建列
    private var columnChannelNames: [String] = []

    // 固定列标识
    private let testNameColumnId = NSUserInterfaceItemIdentifier("testName")
    private let unitColumnId = NSUserInterfaceItemIdentifier("unit")
    private let upperLimitColumnId = NSUserInterfaceItemIdentifier("upperLimit")
    private let lowerLimitColumnId = NSUserInterfaceItemIdentifier("lowerLimit")

    /// 是否只显示存在 FAIL 的测试项行（由主窗口控制面板的"只显示FAIL行"复选框统一控制）
    var showFailOnly: Bool = false {
        didSet {
            // 视图未加载时 tableView 还不存在，只保存值；
            // 视图加载后数据更新走 updateChannelStats → reloadData，自然生效
            guard showFailOnly != oldValue, isViewLoaded else { return }
            tableView.reloadData()
        }
    }

    /// 当前显示的测试项行（只显示 FAIL 时过滤）
    private var displayedTestNames: [String] {
        guard showFailOnly else { return allTestNames }
        return allTestNames.filter { testName in
            dataSource.contains { channel in
                channel.latestTestByName[testName]?.status == "FAIL"
            }
        }
    }

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupUI()
    }

    // MARK: - UI 设置

    private func setupUI() {
        // 顶部标题（只显示FAIL由主窗口控制面板复选框统一控制，此处不设控件）
        let titleLabel = NSTextField(labelWithString: "汇总详情")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 12)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // 滚动视图 + 表格
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.rowHeight = 22
        tableView.headerView = NSTableHeaderView()
        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 5),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -5),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5),
        ])

        // 固定列：测试项（行头）/ Unit / 上限 / 下限
        let testNameColumn = NSTableColumn(identifier: testNameColumnId)
        testNameColumn.title = "测试项"
        testNameColumn.width = 300
        testNameColumn.minWidth = 100
        testNameColumn.maxWidth = 600
        tableView.addTableColumn(testNameColumn)

        let unitColumn = NSTableColumn(identifier: unitColumnId)
        unitColumn.title = "Unit"
        unitColumn.width = 50
        unitColumn.minWidth = 40
        unitColumn.maxWidth = 80
        tableView.addTableColumn(unitColumn)

        let upperColumn = NSTableColumn(identifier: upperLimitColumnId)
        upperColumn.title = "上限"
        upperColumn.width = 50
        upperColumn.minWidth = 50
        upperColumn.maxWidth = 120
        tableView.addTableColumn(upperColumn)

        let lowerColumn = NSTableColumn(identifier: lowerLimitColumnId)
        lowerColumn.title = "下限"
        lowerColumn.width = 50
        lowerColumn.minWidth = 50
        lowerColumn.maxWidth = 120
        tableView.addTableColumn(lowerColumn)
    }

    // MARK: - 数据操作

    /// 更新单个通道数据：增量维护行/列集合，测试项或通道数变化时重建列
    func updateChannelStats(_ channel: Channel) {
        DispatchQueue.main.async {
            // 已结束且不在本轮矩阵中的通道不允许新增：
            // 防止上一轮残留通道通过 .ended 状态回调被重新加回矩阵
            let alreadyPresent = self.dataSource.contains { $0.name == channel.name }
            if channel.status == .ended && !alreadyPresent { return }

            var needRebuildColumns = false

            // 新通道出现 → 需要新增列
            if !alreadyPresent {
                needRebuildColumns = true
            }

            // 合并新测试项（新增行）
            for data in channel.testData where !self.allTestNames.contains(data.testName) {
                self.allTestNames.append(data.testName)
            }

            // 更新/插入通道数据并排序
            if let index = self.dataSource.firstIndex(where: { $0.name == channel.name }) {
                self.dataSource[index] = channel
            } else {
                self.dataSource.append(channel)
                self.dataSource.sort {
                    $0.sortKey.group != $1.sortKey.group
                        ? $0.sortKey.group < $1.sortKey.group
                        : $0.sortKey.slot < $1.sortKey.slot
                }
            }

            if needRebuildColumns {
                self.rebuildColumns()
            }
            self.tableView.reloadData()
        }
    }

    /// 批量更新（仅接收 running 通道；.ended 通道不会被加入新一轮矩阵）
    func updateMultipleChannels(_ channels: [Channel]) {
        DispatchQueue.main.async {
            let channels = channels.filter { $0.status != .ended }
            guard !channels.isEmpty || !self.dataSource.isEmpty else {
                self.tableView.reloadData()
                return
            }
            var needRebuildColumns = false
            for channel in channels {
                if !self.dataSource.contains(where: { $0.name == channel.name }) {
                    needRebuildColumns = true
                }
                for data in channel.testData where !self.allTestNames.contains(data.testName) {
                    self.allTestNames.append(data.testName)
                }
                if let index = self.dataSource.firstIndex(where: { $0.name == channel.name }) {
                    self.dataSource[index] = channel
                } else {
                    self.dataSource.append(channel)
                }
            }
            self.dataSource.sort {
                $0.sortKey.group != $1.sortKey.group
                    ? $0.sortKey.group < $1.sortKey.group
                    : $0.sortKey.slot < $1.sortKey.slot
            }
            if needRebuildColumns {
                self.rebuildColumns()
            }
            self.tableView.reloadData()
        }
    }

    /// 清空所有数据
    func clearAll() {
        dataSource.removeAll()
        allTestNames.removeAll()
        rebuildColumns()
        tableView.reloadData()
    }

    /// 新一轮测试开始：清空上一轮的所有通道列与测试项行，仅重建当前正在运行的通道。
    ///
    /// 背景：DataReaderService 在测试结束后不销毁 Channel 对象（单通道详情需保留历史），
    /// 若某通道未参与新一轮（如上一轮 8 通道、本轮仅 4 通道），其旧数据会残留在矩阵中。
    /// 因此任一通道 restart 时都以"当前 running 通道集合"整体重建：
    /// - 未 restart 的 ended 通道（含未参与本轮的通道）不进入新一轮矩阵；
    /// - 已 restart 通道内存中保留的是各自新一轮已累积的数据，重建不丢失。
    ///
    /// - Parameter runningChannels: 当前状态为 running 的通道列表
    func resetForNewRound(runningChannels: [Channel]) {
        dataSource.removeAll()
        allTestNames.removeAll()
        rebuildColumns()
        updateMultipleChannels(runningChannels)
    }

    // MARK: - 私有方法

    /// 重建通道列（保留前 4 个固定列）
    private func rebuildColumns() {
        while tableView.tableColumns.count > 4 {
            tableView.removeTableColumn(tableView.tableColumns[4])
        }
        for channel in dataSource {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ch_\(channel.name)"))
            column.title = channel.name
            column.width = 90
            column.minWidth = 60
            column.maxWidth = 200
            tableView.addTableColumn(column)
        }
        columnChannelNames = dataSource.map { $0.name }
    }

    /// 取任意通道中该测试项的记录（同一次测试各通道 limit/单位相同）
    private func sampleData(for testName: String) -> TestData? {
        for channel in dataSource {
            if let data = channel.latestTestByName[testName] {
                return data
            }
        }
        return nil
    }
}

// MARK: - NSTableViewDataSource

extension SummaryDetailViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedTestNames.count
    }
}

// MARK: - NSTableViewDelegate

extension SummaryDetailViewController: NSTableViewDelegate {

    /// 单元格视图：固定列显示测试项/单位/上下限，通道列显示该通道测试值（FAIL 红色加粗）
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let columnId = tableColumn?.identifier, row < displayedTestNames.count else { return nil }
        let testName = displayedTestNames[row]
        let cellId = NSUserInterfaceItemIdentifier("cell_\(columnId.rawValue)")
        var cell = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView

        if cell == nil {
            let newCell = NSTableCellView()
            newCell.identifier = cellId
            let textField = NSTextField(labelWithString: "")
            textField.isEditable = false
            textField.isBordered = false
            textField.drawsBackground = false
            textField.lineBreakMode = .byTruncatingTail
            newCell.textField = textField
            newCell.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: newCell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: newCell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: newCell.centerYAnchor),
            ])
            cell = newCell
        }

        guard let textField = cell?.textField else { return cell }

        // 固定列
        if columnId == testNameColumnId {
            textField.stringValue = testName
            textField.textColor = NSColor.labelColor
            textField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            textField.alignment = .left
            return cell
        }

        let sample = sampleData(for: testName)
        if columnId == unitColumnId {
            textField.stringValue = sample?.measurementUnits ?? ""
            textField.textColor = AtlasUtils.secondaryTextColor
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.alignment = .center
            return cell
        }
        if columnId == upperLimitColumnId {
            textField.stringValue = sample?.upperLimit ?? ""
            textField.textColor = AtlasUtils.secondaryTextColor
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.alignment = .center
            return cell
        }
        if columnId == lowerLimitColumnId {
            textField.stringValue = sample?.lowerLimit ?? ""
            textField.textColor = AtlasUtils.secondaryTextColor
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.alignment = .center
            return cell
        }

        // 通道列
        let channelName = columnId.rawValue.replacingOccurrences(of: "ch_", with: "")
        if let channel = dataSource.first(where: { $0.name == channelName }),
           let data = channel.latestTestByName[testName] {
            if data.status == "FAIL" {
                // FAIL 且无测量值时回退显示 "FAIL"，避免单元格全空导致无法定位失败通道
                textField.stringValue = data.measurementValue.isEmpty ? "FAIL" : data.measurementValue
                textField.textColor = NSColor.systemRed
                textField.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            } else {
                textField.stringValue = data.measurementValue
                textField.textColor = NSColor.labelColor
                textField.font = NSFont.systemFont(ofSize: 12)
            }
        } else {
            textField.stringValue = ""
        }
        textField.alignment = .center
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 22
    }

    /// 列头 tooltip：显示测试项完整名（通道列显示通道号）
    func tableView(_ tableView: NSTableView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, row: Int, mouseLocation: NSPoint) -> String {
        guard let columnId = tableColumn?.identifier else { return "" }
        if row >= 0 && row < displayedTestNames.count {
            return "\(displayedTestNames[row]) | \(columnId.rawValue)"
        }
        return columnId.rawValue
    }
}

// HistoryWindowController+Table.swift
// 扁平表格视图代理 — 全部记录展示

import Cocoa

extension HistoryWindowController: NSTableViewDelegate, NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredRecords.count
    }
    
    /// 获取记录的第一个未屏蔽的 fail 测试项信息
    /// 通过 headerRow 查找测试项对应的测量值
    /// 返回 (显示名称, 对应测量值, 测试项位置索引, headerRow列索引)
    func firstUnblockedFailItem(for record: TestRecord) -> (name: String, value: String, pos: Int, idx: Int)? {
        guard record.status == "FAIL" else { return nil }
        
        let testNames = record.testName.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        for i in 0..<testNames.count {
            let name = testNames[i]
            // 跳过已屏蔽的测试项
            if blockedFailures.contains(name) { continue }
            
            // 在 headerRow 中查找该测试项名称，获取对应测量值
            var value = ""
            var colIdx = -1
            if let idx = record.headerRow.firstIndex(of: name) {
                value = idx < record.rowData.count ? record.rowData[idx] : ""
                colIdx = idx
            }
            
            return (name, value, i, colIdx)
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < filteredRecords.count else { return nil }
        let record = filteredRecords[row]
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("FlatCell_\(column.identifier.rawValue)")
        var cell: NSTableCellView
        
        if let reusedCell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView {
            cell = reusedCell
        } else {
            cell = NSTableCellView()
            cell.identifier = cellIdentifier
            
            let textField = ContextMenuTextField()
            textField.isEditable = false
            // 不可选中：避免左键进入 field editor 后右键事件被 NSTextView 接走
            textField.isSelectable = false
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField
            
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        
        // 重置
        cell.textField?.attributedStringValue = NSAttributedString(string: "")
        cell.textField?.textColor = NSColor.labelColor
        
        switch column.identifier.rawValue {
        case "#":
            cell.textField?.stringValue = "\(record.index)"
        case "测试时间":
            cell.textField?.stringValue = record.testTime
        case "SN":
            cell.textField?.stringValue = record.sn
            cell.textField?.textColor = NSColor.systemBlue
        case "SlotID":
            cell.textField?.stringValue = record.slotID
        case "S_BUILD":
            cell.textField?.stringValue = record.sBuild
        case "Status":
            cell.textField?.stringValue = record.status
            cell.textField?.textColor = record.status == "PASS"
                ? NSColor.systemGreen
                : (record.status == "FAIL" ? NSColor.systemRed : NSColor.labelColor)
            cell.textField?.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        case "测试项":
            if let failItem = firstUnblockedFailItem(for: record) {
                cell.textField?.stringValue = failItem.name
                cell.textField?.textColor = NSColor.systemRed
            } else {
                // PASS 记录留空
                cell.textField?.stringValue = ""
            }
        case "测试值":
            if let failItem = firstUnblockedFailItem(for: record) {
                cell.textField?.stringValue = failItem.value
                cell.textField?.textColor = NSColor.systemRed
            } else {
                // PASS 记录留空
                cell.textField?.stringValue = ""
            }
        case "上限值":
            if let failItem = firstUnblockedFailItem(for: record) {
                let upper = (failItem.idx >= 0 && failItem.idx < upperLimitRow.count) ? upperLimitRow[failItem.idx] : ""
                cell.textField?.stringValue = upper
                cell.textField?.textColor = NSColor.systemRed
            } else {
                cell.textField?.stringValue = ""
            }
        case "下限值":
            if let failItem = firstUnblockedFailItem(for: record) {
                let lower = (failItem.idx >= 0 && failItem.idx < lowerLimitRow.count) ? lowerLimitRow[failItem.idx] : ""
                cell.textField?.stringValue = lower
                cell.textField?.textColor = NSColor.systemRed
            } else {
                cell.textField?.stringValue = ""
            }
        default:
            cell.textField?.stringValue = ""
        }
        
        return cell
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    // 点击表头排序（与右键菜单排序共用 currentSortField / sortAscending）
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        let fieldByTitle: [String: String] = [
            "测试时间": "time",
            "SN": "sn",
            "SlotID": "slot"
        ]
        let newField = fieldByTitle[tableColumn.title] ?? "index"

        if currentSortField == newField {
            sortAscending.toggle()
        } else {
            currentSortField = newField
            sortAscending = true
        }
        updateSortIndicator(clickedColumn: tableColumn)
        applyFilters()
    }

    /// 在表头显示排序方向箭头（表头点击与右键菜单排序共用）
    /// clickedColumn 为 nil 时按 currentSortField 自动定位列
    func updateSortIndicator(clickedColumn: NSTableColumn?) {
        let titleByField: [String: String] = [
            "time": "测试时间",
            "sn": "SN",
            "slot": "SlotID"
        ]
        let activeTitle = clickedColumn?.title
            ?? titleByField[currentSortField]
            ?? "#"   // index 排序对应首列

        for column in tableView.tableColumns {
            // 去掉可能已有的箭头后缀，得到原始标题
            let baseTitle = column.title
                .replacingOccurrences(of: " ▲", with: "")
                .replacingOccurrences(of: " ▼", with: "")
            if column.title == activeTitle || baseTitle == activeTitle {
                column.headerCell.stringValue = baseTitle + (sortAscending ? " ▲" : " ▼")
            } else {
                column.headerCell.stringValue = baseTitle
            }
        }
    }
    
    // 右键菜单 — 使用自定义 tableView 子类统一处理跨版本兼容
    func buildContextMenu(row: Int) -> NSMenu? {
        guard row >= 0, row < filteredRecords.count else { return nil }
        
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let record = filteredRecords[row]
        
        let menu = NSMenu(title: "右键菜单")
        
        // 查看详情
        let detailItem = NSMenuItem(title: "查看详情", action: #selector(showDetailFromMenu(_:)), keyEquivalent: "")
        detailItem.representedObject = record
        detailItem.target = self
        menu.addItem(detailItem)
        
        menu.addItem(.separator())
        
        // 打开 Log 文件夹
        let openLogItem = NSMenuItem(title: "打开 Log 文件夹", action: #selector(openLogFolder(_:)), keyEquivalent: "")
        openLogItem.representedObject = record.filePath
        openLogItem.target = self
        menu.addItem(openLogItem)
        
        // 复制 SN
        let copySNItem = NSMenuItem(title: "复制 SN", action: #selector(copySNFromMenu(_:)), keyEquivalent: "")
        copySNItem.representedObject = record.sn
        copySNItem.target = self
        menu.addItem(copySNItem)
        
        // 复制测试项
        let copyTestItem = NSMenuItem(title: "复制测试项", action: #selector(copyTestNameFromMenu(_:)), keyEquivalent: "")
        copyTestItem.representedObject = record.testName
        copyTestItem.target = self
        menu.addItem(copyTestItem)
        
        menu.addItem(.separator())
        
        // 全局屏蔽该 Fail 项（只屏蔽当前显示的第一个 fail 项）
        let blockItem = NSMenuItem(title: "全局屏蔽该 Fail 项", action: #selector(blockGlobalFailureFromMenu(_:)), keyEquivalent: "")
        blockItem.representedObject = record
        blockItem.target = self
        menu.addItem(blockItem)
        
        return menu
    }
    
    @objc func showDetailFromMenu(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? TestRecord else { return }
        showDetailModal(for: record)
    }
    
    @objc func openLogFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let resolvedURL: URL
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            resolvedURL = url
        } else {
            resolvedURL = url.deletingLastPathComponent()
        }
        NSWorkspace.shared.open(resolvedURL)
    }
    
    @objc func copySNFromMenu(_ sender: NSMenuItem) {
        guard let sn = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sn, forType: .string)
    }
    
    @objc func copyTestNameFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
    }
    
    @objc func blockGlobalFailureFromMenu(_ sender: NSMenuItem) {
        guard let record = sender.representedObject as? TestRecord else { return }
        // 只屏蔽当前显示的第一个 fail 测试项，添加到会话屏蔽集（与"已屏蔽fail项"窗口绑定）
        let failName = firstUnblockedFailItem(for: record)?.name ?? record.testName
        sessionBlockedFailures.insert(failName)
        applyFilters()
    }
}

// MARK: - 支持右键菜单 + Enter 键的 TableView 子类
class ContextMenuTableView: NSTableView {
    var contextMenuHandler: ((Int) -> NSMenu?)?
    /// Enter/Return 键回调，参数为当前选中行号
    var enterKeyHandler: (() -> Void)?
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        return contextMenuHandler?(row)
    }
    
    override func keyDown(with event: NSEvent) {
        // Enter / Return 键打开详情
        if event.keyCode == 36, // Return 键
           let handler = enterKeyHandler {
            handler()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - 单元格文本控件（右键转发给所在表格，避免弹出系统文本菜单）
class ContextMenuTextField: NSTextField {
    override func menu(for event: NSEvent) -> NSMenu? {
        // 向上查找所属表格，转成表格坐标后取行号并复用表格的菜单构造逻辑
        var view: NSView? = superview
        while let current = view {
            if let table = current as? ContextMenuTableView,
               let menu = table.contextMenuHandler?(table.row(at: table.convert(event.locationInWindow, from: nil))) {
                return menu
            }
            view = current.superview
        }
        // 不在表格行上时不回退到系统文本菜单
        return nil
    }
}
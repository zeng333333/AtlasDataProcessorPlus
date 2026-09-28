//
//  Channel.swift
//  TestMonitorApp
//
//  Created by Your Name on 2026-01-29.
//

import Cocoa

class Channel: Comparable {
    let group: String
    let slot: String
    var status: ChannelStatus = .waiting
    var failCount: Int = 0
    var passCount: Int = 0
    var totalCount: Int = 0
    var lastUpdate: String = "--"
    var testData: [TestData] = []
    /// 按测试项名缓存最新一条记录（同一次测试同一项可能重复出现，取最新值）
    /// 用于汇总详情矩阵视图按 testName O(1) 查找，避免每个单元格线性扫描
    private var _latestTestByName: [String: TestData]?
    var latestTestByName: [String: TestData] {
        if let cached = _latestTestByName { return cached }
        var map: [String: TestData] = [:]
        for data in testData {
            map[data.testName] = data // 后出现的覆盖先出现的，得到最新值
        }
        _latestTestByName = map
        return map
    }
    var maxRows: Int {
        didSet {
            AppConfig.shared.channelMaxRows = maxRows
        }
    }
    var showFailOnly: Bool = false

    init(group: String, slot: String) {
        self.group = group
        self.slot = slot
        self.maxRows = AppConfig.shared.channelMaxRows
    }

    var name: String {
        return "\(group)-\(slot)"
    }

    /// 用于排序的键（group 数字, slot 数字）
    var sortKey: (group: Int, slot: Int) {
        return AtlasUtils.sortKeyOf(groupSlotName: name)
    }

    static func < (lhs: Channel, rhs: Channel) -> Bool {
        if lhs.sortKey.group != rhs.sortKey.group {
            return lhs.sortKey.group < rhs.sortKey.group
        }
        return lhs.sortKey.slot < rhs.sortKey.slot
    }

    static func == (lhs: Channel, rhs: Channel) -> Bool {
        return lhs.name == rhs.name
    }
    
    func addTestData(_ data: TestData) {
        testData.append(data)
        _latestTestByName = nil // 数据变更，缓存失效
        totalCount += 1
        
        if data.status == "PASS" {
            passCount += 1
        } else if data.status == "FAIL" {
            failCount += 1
        }
        
        // 限制最大行数
        while testData.count > maxRows {
            let removedData = testData.removeFirst()
            if removedData.status == "PASS" {
                passCount -= 1
            } else if removedData.status == "FAIL" {
                failCount -= 1
            }
            totalCount -= 1
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        lastUpdate = formatter.string(from: Date())
    }
    
    func clearData() {
        testData.removeAll()
        _latestTestByName = nil
        failCount = 0
        passCount = 0
        totalCount = 0
        lastUpdate = "--"
    }
    
    enum ChannelStatus: String {
        case waiting = "等待"
        case running = "运行中"
        case ended = "测试结束"
        case stopped = "已停止"
    }
}

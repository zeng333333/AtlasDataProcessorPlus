//
//  DataReaderService.swift
//  TestMonitorApp
//
//  Created by Your Name on 2026-01-29.
//

import Foundation
import os.log

/// 兼容 macOS 10.15 的日志封装（os.Logger 需要 macOS 11+）
struct AtlasLog {
    static let dataReader = OSLog(subsystem: "com.testmonitor.datareader", category: "DataReaderService")

    static func error(_ message: String) {
        os_log("%{public}@", log: dataReader, type: .error, message)
    }

    static func info(_ message: String) {
        os_log("%{public}@", log: dataReader, type: .info, message)
    }
}

protocol DataReaderServiceDelegate: AnyObject {
    func dataReaderService(_ service: DataReaderService, didFindNewDataForChannel channel: Channel, data: [TestData])
    func dataReaderService(_ service: DataReaderService, didUpdateChannelStatus channel: Channel, status: Channel.ChannelStatus)
    func dataReaderService(_ service: DataReaderService, didClearChannelData channel: Channel)
}

/// 监控数据读取服务
///
/// 性能设计（增量读）：
/// - 每 10ms tick 只对每个文件做 1 次 `stat`（attributesOfItem）获取文件大小；
///   保留 10ms 轮询（用户依赖临时文件出现/消失的实时性），CPU 开销由增量读压到 <1%；
/// - 文件有新增字节时，通过常驻 `FileHandle` 从上次偏移量处只读取新增部分，
///   不再全文件重读 + 全量按行切分（旧实现成本 O(文件总大小)，随测试进行线性恶化）；
/// - 末尾不足一行的字节缓存在 `pending` 中，等下一 tick 补齐换行符后再解析。
///
/// 线程安全设计：
/// - 内部状态（monitored/filePositions/ChannelReader）全部封闭在串行 `queue` 上访问；
/// - `Channel` 对象的任何属性修改与 delegate 回调统一派发到主线程执行，
///   消除后台线程与 UI 线程之间的数据竞争。
class DataReaderService {

    static let logger = AtlasLog.self

    weak var delegate: DataReaderServiceDelegate?

    private let basePath: URL

    /// 每个被监控通道的读取状态（仅可在 queue 上访问）
    private final class ChannelReader {
        let channel: Channel
        /// 已从文件读出的字节偏移
        var offset: UInt64 = 0
        /// 尚未凑成完整一行（无换行符）的尾部字节缓存
        var pending = Data()
        /// 常驻文件句柄，避免每次 tick 重新打开文件
        var handle: FileHandle?
        /// 是否已成功 stat 到该文件（用于判断"曾存在后消失"= 测试结束）
        var hasSeenFile = false
        /// 文件是否曾消失（测试结束）。再次出现即视为新一轮测试。
        var fileDisappeared = false
        /// 是否已向 UI 报告过该通道
        var announced = false

        init(channel: Channel) {
            self.channel = channel
        }

        func reset() {
            offset = 0
            pending.removeAll()
            handle?.closeFile()
            handle = nil
        }
    }

    private var monitored: [String: ChannelReader] = [:] // key: "group-slot"
    private var lastScanTime = Date()
    /// QoS 保持 `.background`：10ms 轮询会被系统节流/合并（与 3.0 一致），
    /// 避免 100Hz 准时触发烧满单核；增量读已保证数据完整性，低优先级不影响正确性。
    private let queue = DispatchQueue(label: "com.testmonitor.datareader", qos: .background)
    private var timer: DispatchSourceTimer?

    init(basePath: URL) {
        self.basePath = basePath
    }

    deinit {
        timer?.cancel()
    }

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.timer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.checkFiles()
            }
            timer.resume()
            self.timer = timer

            self.scanChannels()
            self.lastScanTime = Date()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    // MARK: - 定时检查（queue 上执行）

    private func checkFiles() {
        // 每 5 秒扫描一次通道目录
        let now = Date()
        if now.timeIntervalSince(lastScanTime) > 5 {
            scanChannels()
            lastScanTime = now
        }

        for (key, reader) in monitored {
            let filePath = basePath.appendingPathComponent(reader.channel.name)
                .appendingPathComponent("system")
                .appendingPathComponent("records.csv")

            // 一次 stat 同时判断存在性与大小
            let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path)
            guard let fileSize = attributes?[.size] as? UInt64 else {
                // 文件不存在：可能是测试结束
                if !reader.fileDisappeared && reader.hasSeenFile {
                    reader.fileDisappeared = true
                    let channel = reader.channel
                    reader.reset()
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        channel.status = .ended
                        self.delegate?.dataReaderService(self, didUpdateChannelStatus: channel, status: .ended)
                    }
                }
                continue
            }
            reader.hasSeenFile = true

            // 上次消失后文件重新出现，或文件被截断/替换：视为新一轮测试
            if reader.fileDisappeared || fileSize < reader.offset {
                let channel = reader.channel
                let isRestart = reader.fileDisappeared
                reader.reset()
                reader.fileDisappeared = false
                if isRestart {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        channel.clearData()
                        channel.status = .running
                        self.delegate?.dataReaderService(self, didClearChannelData: channel)
                        self.delegate?.dataReaderService(self, didUpdateChannelStatus: channel, status: .running)
                    }
                }
                // 文件被截断但未消失：仅重置偏移，不清 UI 数据（下一轮新数据自然到达）
            }

            if !reader.announced {
                reader.announced = true
                let channel = reader.channel
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    channel.status = .running
                    self.delegate?.dataReaderService(self, didUpdateChannelStatus: channel, status: .running)
                }
            }

            guard fileSize > reader.offset else { continue }

            // 增量读取新增字节
            do {
                if reader.handle == nil {
                    reader.handle = try FileHandle(forReadingFrom: filePath)
                }
                guard let handle = reader.handle else { continue }
                try handle.seek(toOffset: reader.offset)
                let bytesToRead = Int(fileSize - reader.offset)
                let newData: Data
                if #available(macOS 10.15.4, *) {
                    newData = try handle.read(upToCount: bytesToRead) ?? Data()
                } else {
                    // 10.15.0~10.15.3 回退到旧 API（不抛错，EOF 时返回空 Data）
                    newData = handle.readData(ofLength: bytesToRead)
                }
                guard !newData.isEmpty else { continue }

                reader.pending.append(newData)
                reader.offset += UInt64(newData.count)

                // 安全阀：数据长期没有换行符（异常文件）时丢弃缓冲，避免无限增长
                if reader.pending.count > 1_048_576 {
                    Self.logger.error("通道 \(reader.channel.name) 缓冲超过 1MB 且无换行符，已丢弃")
                    reader.pending.removeAll()
                }

                let lines = Self.extractCompleteLines(from: &reader.pending)
                guard !lines.isEmpty else { continue }

                processNewLines(lines, for: reader, key: key)
            } catch {
                Self.logger.error("读取文件失败 \(filePath.path): \(error.localizedDescription)")
                reader.reset()
            }
        }
    }

    /// 从缓冲区中提取所有完整行（以 \n 结尾），剩余不完整部分留在缓冲区
    private static func extractCompleteLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        let newline: UInt8 = 0x0A
        let carriageReturn: UInt8 = 0x0D

        while let idx = buffer.firstIndex(where: { $0 == newline }) {
            var lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            // 兼容 \r\n
            if lineData.last == carriageReturn {
                lineData = lineData.dropLast()
            }
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }

    private func processNewLines(_ lines: [String], for reader: ChannelReader, key: String) {
        var newTestData: [TestData] = []

        for line in lines {
            if line.isEmpty || line.hasPrefix("attributeName,") {
                continue
            }
            if let testData = TestData.parse(from: line) {
                newTestData.append(testData)
            }
        }

        // Channel 状态变更与回调统一在主线程执行（线程安全）
        let channel = reader.channel
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for testData in newTestData {
                channel.addTestData(testData)
            }
            if channel.status != .running {
                channel.status = .running
                self.delegate?.dataReaderService(self, didUpdateChannelStatus: channel, status: .running)
            }
            if !newTestData.isEmpty {
                self.delegate?.dataReaderService(self, didFindNewDataForChannel: channel, data: newTestData)
            }
        }
    }

    private func scanChannels() {
        do {
            let items = try FileManager.default.contentsOfDirectory(at: basePath, includingPropertiesForKeys: nil)
            var foundChannels: Set<String> = []

            for item in items where item.hasDirectoryPath && item.lastPathComponent.contains("-") {
                let nameParts = item.lastPathComponent.split(separator: "-")
                if nameParts.count >= 2 {
                    let group = String(nameParts[0])
                    let slot = String(nameParts[1])
                    let channelKey = "\(group)-\(slot)"

                    // 检查是否有 system/records.csv 文件
                    let recordsFile = item.appendingPathComponent("system").appendingPathComponent("records.csv")
                    if FileManager.default.fileExists(atPath: recordsFile.path) {
                        foundChannels.insert(channelKey)

                        if monitored[channelKey] == nil {
                            let newChannel = Channel(group: group, slot: slot)
                            let reader = ChannelReader(channel: newChannel)
                            reader.hasSeenFile = true
                            reader.announced = true
                            monitored[channelKey] = reader
                            DispatchQueue.main.async { [weak self] in
                                guard let self = self else { return }
                                newChannel.status = .running
                                self.delegate?.dataReaderService(self, didUpdateChannelStatus: newChannel, status: .running)
                            }
                        }
                    }
                }
            }

            // 通道目录消失：标记为测试结束（不主动移除，等待新一轮测试）
            for reader in monitored.values {
                let key = reader.channel.name
                if !foundChannels.contains(key) {
                    // 边沿去重：fileDisappeared 已为 true 说明此前已通知过结束，
                    // 不再每 5 秒重复派发 .ended 回调（否则 UI 侧会反复收到已结束通道）
                    if reader.fileDisappeared { continue }
                    let channel = reader.channel
                    reader.reset()
                    reader.fileDisappeared = true
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        channel.status = .ended
                        self.delegate?.dataReaderService(self, didUpdateChannelStatus: channel, status: .ended)
                    }
                }
            }
        } catch {
            Self.logger.error("扫描通道目录失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 查询（线程安全）

    func getChannels() -> [Channel] {
        return queue.sync {
            monitored.values.map { $0.channel }
        }
    }

    func getChannel(for key: String) -> Channel? {
        return queue.sync {
            monitored[key]?.channel
        }
    }
}

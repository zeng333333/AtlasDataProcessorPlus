// File: AtlasDataProcessor.swift (修复版)
import Foundation
import AppKit

// ==================== 数据结构定义 ====================
struct CSVRow {
    var attributeName: String = ""
    var attributeValue: String = ""
    var testName: String = ""
    var subTestName: String = ""
    var subSubTestName: String = ""
    var relaxedUpperLimit: String = ""
    var upperLimit: String = ""
    var measurementValue: String = ""
    var lowerLimit: String = ""
    var relaxedLowerLimit: String = ""
    var measurementUnits: String = ""
    var priority: String = ""
    var status: String = ""
    var failureMessage: String = ""
    var startTime: String = ""
    var stopTime: String = ""
    var timeInterval: String = ""
}

struct FileProcessResult {
    var attrNames: [String] = []
    var measureNames: [String] = []
    var measureMeta: [String: [String: String]] = [:]
    var attrDict: [String: String] = [:]
    var measureDict: [String: String] = [:]
    var infoRow: [String] = Array(repeating: "", count: 12)
    var filePathRow: [String] = [""]
}

struct GHConfig {
    var site: String = ""
    var product: String = ""
    var stationId: String = ""
    
    static func loadFromJson(path: String) -> GHConfig {
        var config = GHConfig()
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ghinfo = json["ghinfo"] as? [String: Any] else {
            print("无法打开GH配置文件: \(path)")
            return config
        }
        
        config.site = ghinfo["SITE"] as? String ?? ""
        config.product = ghinfo["PRODUCT"] as? String ?? ""
        config.stationId = ghinfo["STATION_ID"] as? String ?? ""
        
        return config
    }
}

// MARK: - 工具函数
enum AtlasUtils {

    // MARK: 小屏适配（工厂老显示器常见 1024×768 / 1366×768）

    /// 主屏可用区域（扣除菜单栏/Dock）
    static var visibleFrame: NSRect {
        NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    /// 是否为小屏（可用区域任一边不足 1200×800）
    static var isCompactScreen: Bool {
        let f = visibleFrame
        return f.width < 1200 || f.height < 800
    }

    /// 将期望窗口尺寸钳制到主屏可用区域内（四周留 20pt 边距）
    static func clampedWindowSize(preferred: NSSize) -> NSSize {
        let f = visibleFrame
        let maxWidth = f.width - 40
        let maxHeight = f.height - 40
        return NSSize(
            width: min(preferred.width, maxWidth),
            height: min(preferred.height, maxHeight)
        )
    }

    // MARK: 主题色（自动适配明暗模式）

    /// FAIL 行背景色（浅色模式淡红，深色模式深红）
    static let failRowBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.35, green: 0.12, blue: 0.12, alpha: 1.0)
            : NSColor(red: 1.0, green: 0.85, blue: 0.85, alpha: 1.0)
    }

    /// 普通行背景色（跟随窗口）
    static let defaultRowBackground = NSColor.windowBackgroundColor

    /// 次要文本颜色
    static let secondaryTextColor = NSColor.secondaryLabelColor

    // MARK: CSV 转义

    /// CSV 单元格转义：包含逗号/引号/换行时用双引号包裹并转义内部引号
    static func escapeCSV(_ cell: String) -> String {
        if cell.contains(",") || cell.contains("\"") || cell.contains("\n") || cell.contains("\r") {
            return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return cell
    }

    /// 将 CSV 内容写入指定 URL（带 UTF-8 BOM，Excel 可正确识别中文）
    /// 失败时弹出错误提示框并返回 false
    @discardableResult
    static func writeCSV(_ content: String, to url: URL, context: String) -> Bool {
        // BOM 让 Excel 以 UTF-8 打开，避免中文乱码
        let bomContent = "\u{FEFF}" + content
        do {
            try bomContent.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "\(context)失败"
            alert.informativeText = "\(error.localizedDescription)\n\n目标位置：\(url.path)"
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    // MARK: 搜索

    /// 空格分隔多关键词 AND 匹配：所有关键词都命中任一字段才算匹配
    /// 例："sn123 voltage" 要求同时包含 sn123 和 voltage
    static func matchesAllKeywords(_ searchText: String, in fields: [String]) -> Bool {
        let keywords = searchText.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard !keywords.isEmpty else { return true }
        let haystack = fields.map { $0.lowercased() }.joined(separator: "\n")
        return keywords.allSatisfy { haystack.contains($0) }
    }

    // MARK: 通道排序

    /// 按 group 数字、slot 数字升序排序通道
    static func sortedChannels(_ channels: [Channel]) -> [Channel] {
        return channels.sorted { $0.sortKey < $1.sortKey }
    }

    /// 按 group-slot 排序通道名称
    static func sortedChannelNames(_ names: [String]) -> [String] {
        return names.sorted { name1, name2 in
            let key1 = Self.sortKeyOf(groupSlotName: name1)
            let key2 = Self.sortKeyOf(groupSlotName: name2)
            if key1 != key2 { return key1 < key2 }
            return name1 < name2
        }
    }

    /// "group3-slot12" → (3, 12)；解析失败按 0 处理
    static func sortKeyOf(groupSlotName: String) -> (group: Int, slot: Int) {
        let parts = groupSlotName.components(separatedBy: "-")
        guard parts.count >= 2 else { return (0, 0) }
        let group = Int(parts[0].replacingOccurrences(of: "group", with: "")) ?? 0
        let slot = Int(parts[1].replacingOccurrences(of: "slot", with: "")) ?? 0
        return (group, slot)
    }

    static func split(_ str: String, delimiter: Character) -> [String] {
        // 使用 split(omittingEmptySubsequences: false) 来保留空值
        return str.split(separator: delimiter, 
                        maxSplits: Int.max, 
                        omittingEmptySubsequences: false)
                .map(String.init)
    }
        
    static func trim(_ str: String) -> String {
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func readCSVFile(filePath: String) -> [CSVRow] {
        var rows: [CSVRow] = []
        
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            print("无法打开文件: \(filePath)")
            return rows
        }
        
        let lines = content.components(separatedBy: .newlines)
        var isFirstLine = true
        
        for line in lines {
            let trimmedLine = trim(line)
            guard !trimmedLine.isEmpty else { continue }
            
            if isFirstLine {
                isFirstLine = false
                continue // 跳过标题行
            }
            var tokens = split(trimmedLine, delimiter: ",")
            if tokens.count < 17 {
                tokens.append(contentsOf: Array(repeating: "", count: 17 - tokens.count))
            }
            
            var row = CSVRow()
            row.attributeName = trim(tokens[0])
            row.attributeValue = trim(tokens[1])
            row.testName = trim(tokens[2])
            row.subTestName = trim(tokens[3])
            row.subSubTestName = trim(tokens[4])
            row.relaxedUpperLimit = trim(tokens[5])
            row.upperLimit = trim(tokens[6])
            row.measurementValue = trim(tokens[7])
            row.lowerLimit = trim(tokens[8])
            row.relaxedLowerLimit = trim(tokens[9])
            row.measurementUnits = trim(tokens[10])
            row.priority = trim(tokens[11])
            row.status = trim(tokens[12])
            row.failureMessage = trim(tokens[13])
            row.startTime = trim(tokens[14])
            row.stopTime = trim(tokens[15])
            row.timeInterval = trim(tokens[16])
            rows.append(row)
        }
        
        return rows
    }
}

// MARK: - AtlasDataProcessor 类
class AtlasDataProcessor {
    
    // MARK: - 私有属性
    private var recordsFiles: [String] = []
    private var ghConfig = GHConfig()
    private var allAttributeNames: [String] = []
    private var allMeasureNames: [String] = []
    private var allAttrSeen = Set<String>()
    private var allMeasureSeen = Set<String>()
    private var measureMetaDict: [String: [String: String]] = [:]
    private var fileResults: [FileProcessResult] = []
    
    private var sortedAttrNames: [String] = []
    private var sortedMeasureNames: [String] = []
    private var allParamNames: [String] = []
    
    private var unitRow: [String] = []
    private var upperLimitRow: [String] = []
    private var lowerLimitRow: [String] = []
    
    private(set) var finalData: [[String]] = []
    private(set) var finalDataPlus: [[String]] = []
    
    private let fixedColumns = 12
    private let timestamp: String
    
    // MARK: - 公开接口
    var processedCount: Int { return recordsFiles.count }
    var parameterCount: Int { return allParamNames.count }
    var failureCount: Int { return extractFailInfo().count }
    
    // MARK: - 初始化
    init() {
        // 生成时间戳
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        formatter.timeZone = TimeZone.current
        timestamp = formatter.string(from: Date())
        
        // 加载GH配置
        let ghPath = "/vault/data_collection/test_station_config/gh_station_info.json"
        ghConfig = GHConfig.loadFromJson(path: ghPath)
    }
    
    // MARK: - 主运行函数
    func run(rootPath: String = "./mnt") -> Bool {
        let startTotal = Date()
        
        print("🚀 开始执行 Atlas 数据处理...")
        
        guard scanRecordsFiles(rootPath: rootPath) else {
            print("❌ 未找到文件，退出")
            return false
        }
        
        collectAllParameters()
        buildFinalData()
        
        let endTotal = Date()
        let duration = endTotal.timeIntervalSince(startTotal)
        
        print("\n✅ 处理完成")
        print("=== 总处理耗时: \(String(format: "%.3f", duration))s ===")
        print("📊 统计信息:")
        print("   - 处理文件数: \(recordsFiles.count)")
        print("   - 属性参数: \(sortedAttrNames.count)")
        print("   - 测量参数: \(sortedMeasureNames.count)")
        print("   - 总参数: \(allParamNames.count)")
        
        let failInfo = extractFailInfo()
        if !failInfo.isEmpty {
            print("⚠️  失败记录: \(failInfo.count) 条")
        }
        
        return true
    }
    
    // MARK: - 辅助方法
    
    func saveOutput(outputDir: String = "./mnt") -> String? {
        let start = Date()
        
        guard !finalData.isEmpty else {
            print("❌ 没有数据可保存")
            return nil
        }
        
        let outputFilename = "AtlasCombineData_MultiRow_\(timestamp).csv"
        let outputPath = (outputDir as NSString).appendingPathComponent(outputFilename)
        
        print("💾 保存文件到: \(outputPath)")
        
        do {
            let csvContent = finalData.map { row in
                row.map { cell in
                    // CSV转义处理
                    if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                        let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
                        return "\"\(escaped)\""
                    }
                    return cell
                }.joined(separator: ",")
            }.joined(separator: "\n")
            
            try csvContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
            
            // 验证文件
            let attributes = try FileManager.default.attributesOfItem(atPath: outputPath)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            let end = Date()
            let duration = end.timeIntervalSince(start)
            
            print("✅ 文件保存成功")
            print("   - 文件大小: \(String(format: "%.2f", Double(fileSize) / 1024.0)) KB")
            print("   - 总行数: \(finalData.count)")
            print("   - 保存耗时: \(String(format: "%.3f", duration))s")
            
            return outputPath
            
        } catch {
            print("❌ 无法创建输出文件: \(error)")
            return nil
        }
    }
    
    func saveOutputPlus(outputDir: String = "./mnt") -> String? {
        let start = Date()
        
        guard !finalDataPlus.isEmpty else {
            print("❌ 没有Plus数据可保存")
            return nil
        }
        
        let outputFilename = "AtlasCombineData_MultiRow_Plus_\(timestamp).csv"
        let outputPath = (outputDir as NSString).appendingPathComponent(outputFilename)
        
        print("💾 保存Plus文件到: \(outputPath)")
        
        do {
            let csvContent = finalDataPlus.map { row in
                row.map { cell in
                    // CSV转义处理
                    if cell.contains(",") || cell.contains("\"") || cell.contains("\n") {
                        let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
                        return "\"\(escaped)\""
                    }
                    return cell
                }.joined(separator: ",")
            }.joined(separator: "\n")
            
            try csvContent.write(toFile: outputPath, atomically: true, encoding: .utf8)
            
            let attributes = try FileManager.default.attributesOfItem(atPath: outputPath)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            let end = Date()
            let duration = end.timeIntervalSince(start)
            
            print("✅ Plus文件保存成功")
            print("   - 文件大小: \(String(format: "%.2f", Double(fileSize) / 1024.0)) KB")
            print("   - 总行数: \(finalDataPlus.count)")
            print("   - 保存耗时: \(String(format: "%.3f", duration))s")
            
            return outputPath
            
        } catch {
            print("❌ 无法创建Plus输出文件: \(error)")
            return nil
        }
    }
    
    // MARK: - 异步版本（适合UI应用）
    func runAsync(rootPath: String = "./mnt", 
                  progress: ((Float, String) -> Void)? = nil,
                  completion: @escaping (Bool, String?, Error?) -> Void) {
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            do {
                let start = Date()
                
                // 扫描文件
                progress?(0.0, "正在扫描文件...")
                guard self.scanRecordsFiles(rootPath: rootPath) else {
                    throw NSError(domain: "AtlasDataProcessor", 
                                code: 404, 
                                userInfo: [NSLocalizedDescriptionKey: "未找到文件"])
                }
                
                progress?(0.2, "正在处理 \(self.recordsFiles.count) 个文件...")
                
                // 收集参数
                self.collectAllParameters()
                progress?(0.6, "正在构建数据表...")
                
                // 构建数据
                self.buildFinalData()
                
                let end = Date()
                let duration = end.timeIntervalSince(start)
                
                let message = """
                处理完成！
                - 文件数: \(self.recordsFiles.count)
                - 参数数: \(self.allParamNames.count)
                - 耗时: \(String(format: "%.2f", duration))s
                """
                
                DispatchQueue.main.async {
                    completion(true, message, nil)
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(false, nil, error)
                }
            }
        }
    }
    
    // MARK: - 数据分析方法
    
    func getStatistics() -> [String: Any] {
        let failInfo = extractFailInfo()
        
        return [
            "total_files": recordsFiles.count,
            "total_rows": finalData.count - 4, // 减去标题行
            "attribute_params": sortedAttrNames.count,
            "measure_params": sortedMeasureNames.count,
            "total_params": allParamNames.count,
            "failure_count": failInfo.count,
            "success_rate": recordsFiles.count > 0 ? 
                Double(recordsFiles.count - failInfo.count) / Double(recordsFiles.count) * 100 : 0,
            "timestamp": timestamp
        ]
    }
    
    func getFailureSummary(snColumnName: String = "", channelColumnName: String = "", sBuildColumnName: String = "") -> [String] {
        var result: [String] = []
        
        // 固定的标题行（与 infoRow 对应）
        let headerRow = [
            "site", "Product", "SerialNumber", "Special Build Name",
            "Special Build Description", "Unit Number", "Station ID",
            "Test Pass/Fail Status", "StartTime", "EndTime", "Version",
            "List of Failing Tests"
        ]
        
        // 查找 SN、通道号和 S_BUILD 列的索引
        let snIndex = headerRow.firstIndex(of: snColumnName) ?? -1
        let channelIndex = headerRow.firstIndex(of: channelColumnName) ?? -1
        let sBuildIndex = headerRow.firstIndex(of: sBuildColumnName) ?? -1
        
        // 遍历所有文件结果
        for fileResult in fileResults {
            let testStatus = fileResult.infoRow[7]
            if testStatus == "FAIL" {
                let time = fileResult.infoRow[9] // EndTime
                let path = fileResult.filePathRow[0]
                let failTests = fileResult.infoRow[11]
                
                // 从 infoRow 中获取 SN、通道号和 S_BUILD
                var sn = (snIndex >= 0 && snIndex < fileResult.infoRow.count) ? fileResult.infoRow[snIndex] : ""
                var channel = (channelIndex >= 0 && channelIndex < fileResult.infoRow.count) ? fileResult.infoRow[channelIndex] : ""
                var sBuild = (sBuildIndex >= 0 && sBuildIndex < fileResult.infoRow.count) ? fileResult.infoRow[sBuildIndex] : ""
                
                #if DEBUG
                // 打印 debug 信息
                print("🔍 getFailureSummary: snColumnName=\(snColumnName), channelColumnName=\(channelColumnName), sBuildColumnName=\(sBuildColumnName)")
                // 打印从 infoRow 获取的结果
                print("📋 从 infoRow 获取: sn=\(sn), channel=\(channel), sBuild=\(sBuild)")
                #endif
                
                // 如果 infoRow 中没有，尝试从不固定列（属性和测量）中获取
                if sn.isEmpty {
                    // 从属性字典中获取 SN
                    if let snValue = fileResult.attrDict[snColumnName] {
                        sn = snValue
                        #if DEBUG
                        print("📋 从 attrDict 获取 SN: \(sn)")
                        #endif
                    } else if let snValue = fileResult.measureDict[snColumnName] {
                        // 从测量字典中获取 SN
                        sn = snValue
                        #if DEBUG
                        print("📋 从 measureDict 获取 SN: \(sn)")
                        #endif
                    }
                }
                
                if channel.isEmpty {
                    // 从属性字典中获取通道号
                    if let channelValue = fileResult.attrDict[channelColumnName] {
                        channel = channelValue
                        #if DEBUG
                        print("📋 从 attrDict 获取通道号: \(channel)")
                        #endif
                    } else if let channelValue = fileResult.measureDict[channelColumnName] {
                        // 从测量字典中获取通道号
                        channel = channelValue
                        #if DEBUG
                        print("📋 从 measureDict 获取通道号: \(channel)")
                        #endif
                    }
                }
                
                if sBuild.isEmpty {
                    // 从属性字典中获取 S_BUILD
                    if let sBuildValue = fileResult.attrDict[sBuildColumnName] {
                        sBuild = sBuildValue
                        #if DEBUG
                        print("📋 从 attrDict 获取 S_BUILD: \(sBuild)")
                        #endif
                    } else if let sBuildValue = fileResult.measureDict[sBuildColumnName] {
                        // 从测量字典中获取 S_BUILD
                        sBuild = sBuildValue
                        #if DEBUG
                        print("📋 从 measureDict 获取 S_BUILD: \(sBuild)")
                        #endif
                    }
                }
                
                #if DEBUG
                // 打印最终结果
                print("✅ 最终获取: sn=\(sn), channel=\(channel), sBuild=\(sBuild)")
                #endif
                
                // 按分号分割失败用例
                let testCases = failTests.components(separatedBy: ";")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                if testCases.isEmpty {
                    // 如果没有具体的失败用例，保留一行
                    result.append("\(time) | 无具体用例 | \(path) | | | | \(sn) | \(channel) | \(sBuild)")
                } else {
                    // 将每个失败用例单独作为一行
                    for testCase in testCases {
                        // 获取该失败用例的元数据和值
                        let upperLimit = fileResult.measureMeta[testCase]?["upper"] ?? ""
                        let lowerLimit = fileResult.measureMeta[testCase]?["lower"] ?? ""
                        let value = fileResult.measureDict[testCase] ?? ""
                        
                        result.append("\(time) | \(testCase) | \(path) | \(upperLimit) | \(lowerLimit) | \(value) | \(sn) | \(channel) | \(sBuild)")
                    }
                }
            }
        }
        
        return result
    }
    
    // 从文件路径中提取指定键的值
    private func extractValueFromFilePath(_ filePath: String, key: String) -> String {
        // 示例文件路径格式：.../Key=Value/...
        let pattern = "\\b\(key)\\s*=\\s*([^/]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: filePath, options: [], range: NSRange(location: 0, length: filePath.utf16.count)) {
            if let valueRange = Range(match.range(at: 1), in: filePath) {
                return String(filePath[valueRange])
            }
        }
        return ""
    }
    
    func exportToJSON(outputDir: String) -> String? {
        let stats = getStatistics()
        let failSummary = getFailureSummary(snColumnName: "", channelColumnName: "")
        
        let exportData: [String: Any] = [
            "metadata": stats,
            "failures": failSummary,
            "parameters": [
                "attributes": sortedAttrNames,
                "measures": sortedMeasureNames
            ],
            "processed_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        let filename = "AtlasAnalysis_\(timestamp).json"
        let path = (outputDir as NSString).appendingPathComponent(filename)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, 
                                                    options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            print("❌ JSON导出失败: \(error)")
            return nil
        }
    }
}

// MARK: - 私有扩展：文件扫描
private extension AtlasDataProcessor {
    func scanRecordsFiles(rootPath: String) -> Bool {
        let start = Date()
        
        print("开始扫描目录: \(rootPath)")
        
        func scanDirectory(_ dirPath: String) {
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: dirPath),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                print("无法打开目录: \(dirPath)")
                return
            }
            
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      resourceValues.isRegularFile == true,
                      fileURL.lastPathComponent == "records.csv" else {
                    continue
                }
                
                recordsFiles.append(fileURL.path)
            }
        }
        
        scanDirectory(rootPath)
        
        let end = Date()
        let duration = end.timeIntervalSince(start)
        
        print("扫描到 \(recordsFiles.count) 个文件，耗时 \(String(format: "%.3f", duration))s")
        
        return !recordsFiles.isEmpty
    }
}

// MARK: - 私有扩展：时间格式转换
private extension AtlasDataProcessor {
    func convertTimeFormat(_ timeInput: String) -> String {
        let timeStr = AtlasUtils.trim(timeInput)
        
        if timeStr.isEmpty {
            return ""
        }
        
        var cleanedTime = timeStr
        
        // 预处理1：中文时段与月份归一化
        // 支持 "6月 18 2025 4:24:34.3390 下午" 这类其他平台的格式
        cleanedTime = cleanedTime.replacingOccurrences(of: "上午", with: "AM")
        cleanedTime = cleanedTime.replacingOccurrences(of: "下午", with: "PM")
        cleanedTime = cleanedTime.replacingOccurrences(
            of: #"(\d{1,2})\s*月"#,
            with: "$1",
            options: .regularExpression
        )
        cleanedTime = cleanedTime.replacingOccurrences(of: "月", with: "")
        
        // 预处理2：只移除小数秒（含其后的空白），保留末尾的 AM/PM
        // 例："Nov 16 2026 1:14:29.2130 PM" -> "Nov 16 2026 1:14:29 PM"
        cleanedTime = cleanedTime.replacingOccurrences(
            of: #"\.\d+\s*"#,
            with: " ",
            options: .regularExpression
        )
        
        // 预处理3：压缩多余空白，兼容单/双位月日与不规则空格
        cleanedTime = cleanedTime.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        
        // 调试信息
        #if DEBUG
        print("尝试转换时间: \(cleanedTime)")
        #endif
        
        // 含 AM/PM 时只按 12 小时制解析，避免 PM 丢失后被 24 小时制格式静默误判
        let hasMeridiem = cleanedTime.hasSuffix("AM") || cleanedTime.hasSuffix("PM")
        
        let twelveHourFormats = [
            "MMM d yyyy h:mm:ss a",   // Jun 18 2025 4:24:34 PM
            "MMM dd yyyy h:mm:ss a",  // Nov 16 2026 1:14:29 PM
            "M d yyyy h:mm:ss a",     // 6 18 2025 4:24:34 PM（中文月份转数字）
            "MM/dd/yyyy h:mm:ss a",
            "dd/MM/yyyy h:mm:ss a"
        ]
        
        let twentyFourHourFormats = [
            "yyyy-MM-dd HH:mm:ss",      // 2025-06-18 16:36:40
            "yyyy/MM/dd HH:mm:ss",      // 2025/06/18 16:36:40
            "MM/dd/yyyy HH:mm:ss",      // 01/19/2026 19:53:45
            "dd/MM/yyyy HH:mm:ss",      // 19/01/2026 19:53:45
            "MMM d yyyy HH:mm:ss",      // Jun 18 2025 16:36:40
            "MMM dd yyyy HH:mm:ss",     // Jan 19 2026 19:53:45
            "yyyy-MM-dd'T'HH:mm:ss"     // ISO格式
        ]
        
        let formats = hasMeridiem ? twelveHourFormats : twentyFourHourFormats
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleanedTime) {
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let result = formatter.string(from: date)
                #if DEBUG
                print("成功转换: \(result) (格式: \(format))")
                #endif
                return result
            }
        }
        
        // 兜底：无法识别时原样返回，避免数据丢失
        print("时间格式转换失败: \(timeInput)")
        return timeInput
    }
}

// MARK: - 私有扩展：处理单个文件
private extension AtlasDataProcessor {
    func processSingleFile(filePath: String) -> FileProcessResult {
        var result = FileProcessResult()
        result.filePathRow[0] = filePath
        
        let rows = AtlasUtils.readCSVFile(filePath: filePath)
        if rows.isEmpty {
            return result
        }
        
        // 提取Attribute（保序去重）
        var attrDict: [String: String] = [:]
        var attrNamesList: [String] = []
        var attrSeen = Set<String>()

        for row in rows where !row.attributeName.isEmpty {
            if !attrSeen.contains(row.attributeName) {
                attrSeen.insert(row.attributeName)
                attrNamesList.append(row.attributeName)
            }
            attrDict[row.attributeName] = row.attributeValue
        }

        result.attrNames = attrNamesList
        result.attrDict = attrDict

        // 提取Measure（保序去重）
        var measureDict: [String: String] = [:]
        var measureMeta: [String: [String: String]] = [:]
        var measureNamesList: [String] = []
        var measureSeen = Set<String>()

        for row in rows where !row.measurementValue.isEmpty {
            let fullParamName = "\(row.testName) \(row.subTestName) \(row.subSubTestName)"
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !fullParamName.isEmpty {
                if !measureSeen.contains(fullParamName) {
                    measureSeen.insert(fullParamName)
                    measureNamesList.append(fullParamName)
                }
                measureDict[fullParamName] = row.measurementValue

                // 存储元数据（只取第一个）
                if measureMeta[fullParamName] == nil {
                    let meta: [String: String] = [
                        "unit": row.measurementUnits,
                        "upper": row.upperLimit,
                        "lower": row.lowerLimit
                    ]
                    measureMeta[fullParamName] = meta
                }
            }
        }

        result.measureNames = measureNamesList
        result.measureMeta = measureMeta
        result.measureDict = measureDict
        
        // 提取固定信息
        let sn = attrDict["PrimaryIdentity"] ?? ""
        
        var testStatus = "PASS"
        for row in rows where row.status == "FAIL" {
            testStatus = "FAIL"
            break
        }
        
        var startTime = ""
        var endTime = ""
        for row in rows {
            if !row.startTime.isEmpty && startTime.isEmpty {
                startTime = convertTimeFormat(row.startTime)
            }
            if !row.stopTime.isEmpty && endTime.isEmpty {
                endTime = convertTimeFormat(row.stopTime)
            }
            if !startTime.isEmpty && !endTime.isEmpty {
                break
            }
        }
        
        let version = attrDict["SwVersion"] ?? ""
        
        var failTests = ""
        if testStatus == "FAIL" {
            var failTestList: [String] = []
            var failSeen = Set<String>()
            for row in rows where row.status == "FAIL" {
                let failIdentifier = "\(row.testName) \(row.subTestName) \(row.subSubTestName)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !failIdentifier.isEmpty && !failSeen.contains(failIdentifier) {
                    failSeen.insert(failIdentifier)
                    failTestList.append(failIdentifier)
                }
            }
            failTests = failTestList.joined(separator: "; ")
        }
        
        // 构建固定行
        result.infoRow[0] = ghConfig.site
        result.infoRow[1] = ghConfig.product
        result.infoRow[2] = sn
        result.infoRow[3] = ""
        result.infoRow[4] = ""
        result.infoRow[5] = ""
        result.infoRow[6] = ghConfig.stationId
        result.infoRow[7] = testStatus
        result.infoRow[8] = startTime
        result.infoRow[9] = endTime
        result.infoRow[10] = version
        result.infoRow[11] = failTests
        
        return result
    }
}

// MARK: - 私有扩展：收集所有参数
private extension AtlasDataProcessor {
    func collectAllParameters() {
        let start = Date()
        
        print("开始单线程处理...")
        
        // 顺序处理每个文件（单线程）
        for filePath in recordsFiles {
            let result = processSingleFile(filePath: filePath)
            fileResults.append(result)

            // 合并参数名（保序去重，保留首次出现顺序）
            for attr in result.attrNames {
                if !allAttrSeen.contains(attr) {
                    allAttrSeen.insert(attr)
                    allAttributeNames.append(attr)
                }
            }
            for measure in result.measureNames {
                if !allMeasureSeen.contains(measure) {
                    allMeasureSeen.insert(measure)
                    allMeasureNames.append(measure)
                }
            }

            // 合并元数据
            for (key, meta) in result.measureMeta {
                if measureMetaDict[key] == nil {
                    measureMetaDict[key] = meta
                }
            }
        }

        // 保留原始顺序，不再排序
        sortedAttrNames = allAttributeNames
        sortedMeasureNames = allMeasureNames

        // 合并所有参数名
        allParamNames = sortedAttrNames
        allParamNames.append(contentsOf: sortedMeasureNames)
        
        // 生成单位/上下限行
        let totalParamsCount = sortedAttrNames.count + sortedMeasureNames.count
        unitRow = Array(repeating: "", count: totalParamsCount)
        upperLimitRow = Array(repeating: "", count: totalParamsCount)
        lowerLimitRow = Array(repeating: "", count: totalParamsCount)
        
        // Attribute部分为空（保持原有位置）
        for i in 0..<sortedAttrNames.count {
            unitRow[i] = ""
            upperLimitRow[i] = ""
            lowerLimitRow[i] = ""
        }
        
        // Measure部分
        for i in 0..<sortedMeasureNames.count {
            let param = sortedMeasureNames[i]
            let idx = sortedAttrNames.count + i
            
            if let meta = measureMetaDict[param] {
                unitRow[idx] = meta["unit"] ?? ""
                upperLimitRow[idx] = meta["upper"] ?? ""
                lowerLimitRow[idx] = meta["lower"] ?? ""
                // #if DEBUG
                // print("   - Measure参数[\(i)] \(param): unit=\(meta["unit"] ?? ""), upper=\(meta["upper"] ?? ""), lower=\(meta["lower"] ?? "")")
                // #endif
            }
        }
        
        let end = Date()
        let duration = end.timeIntervalSince(start)
        
        print("单线程处理耗时: \(String(format: "%.3f", duration))s")
        print("属性参数数量: \(sortedAttrNames.count)")
        print("测量参数数量: \(sortedMeasureNames.count)")
    }
}

// MARK: - 私有扩展：构建最终数据
private extension AtlasDataProcessor {
    func buildFinalData() {
        let start = Date()
        
        let totalCols = fixedColumns + allParamNames.count
        
        // 构建标题行
        var headerRow: [String] = [
            "site", "Product", "SerialNumber", "Special Build Name",
            "Special Build Description", "Unit Number", "Station ID",
            "Test Pass/Fail Status", "StartTime", "EndTime", "Version",
            "List of Failing Tests"
        ]
        headerRow.append(contentsOf: allParamNames)
        
        // 构建plus版的标题行（包含文件路径）
        var headerRowPlus = headerRow
        headerRowPlus.insert("file_path", at: 12) // 在"List of Failing Tests"之后
        
        // 构建上限行
        var upperRow: [String] = ["Upper Limit ----->"]
        upperRow.append(contentsOf: Array(repeating: "", count: 11))
        upperRow.append(contentsOf: upperLimitRow)
        
        var upperRowPlus: [String] = ["Upper Limit ----->"]
        upperRowPlus.append(contentsOf: Array(repeating: "", count: 12))
        upperRowPlus.append(contentsOf: upperLimitRow)
        
        // 构建下限行
        var lowerRow: [String] = ["Lower Limit ----->"]
        lowerRow.append(contentsOf: Array(repeating: "", count: 11))
        lowerRow.append(contentsOf: lowerLimitRow)
        
        var lowerRowPlus: [String] = ["Lower Limit ----->"]
        lowerRowPlus.append(contentsOf: Array(repeating: "", count: 12))
        lowerRowPlus.append(contentsOf: lowerLimitRow)
        
        // 构建单位行
        var unitRowFull: [String] = ["Measurement Unit ----->"]
        unitRowFull.append(contentsOf: Array(repeating: "", count: 11))
        unitRowFull.append(contentsOf: unitRow)
        
        var unitRowPlus: [String] = ["Measurement Unit ----->"]
        unitRowPlus.append(contentsOf: Array(repeating: "", count: 12))
        unitRowPlus.append(contentsOf: unitRow)
        
        // 清空并初始化最终数据
        finalData.removeAll()
        finalDataPlus.removeAll()
        
        // 添加空行（原始代码中有）
        finalData.append(Array(repeating: "", count: totalCols))
        
        // 添加标题行
        finalData.append(headerRow)
        finalData.append(upperRow)
        finalData.append(lowerRow)
        finalData.append(unitRowFull)
        
        finalDataPlus.append(headerRowPlus)
        finalDataPlus.append(upperRowPlus)
        finalDataPlus.append(lowerRowPlus)
        finalDataPlus.append(unitRowPlus)
        
        // 添加数据行
        for result in fileResults {
            var row: [String] = []
            var rowPlus: [String] = []
            
            // 固定列
            for i in 0..<fixedColumns {
                let value = i < result.infoRow.count ? result.infoRow[i] : ""
                row.append(value)
                rowPlus.append(value)
            }
            
            // 文件路径（仅plus版）
            let filePath = result.filePathRow.isEmpty ? "" : result.filePathRow[0]
            rowPlus.append(filePath)
            
            // Attribute值
            for attrName in sortedAttrNames {
                let value = result.attrDict[attrName] ?? ""
                row.append(value)
                rowPlus.append(value)
            }
            
            // Measure值
            for measureName in sortedMeasureNames {
                let value = result.measureDict[measureName] ?? ""
                row.append(value)
                rowPlus.append(value)
            }
            
            finalData.append(row)
            finalDataPlus.append(rowPlus)
        }
        
        let end = Date()
        let duration = end.timeIntervalSince(start)
        
        print("构建最终数据耗时: \(String(format: "%.3f", duration))s")
        print("标准数据行数: \(finalData.count)")
        print("Plus数据行数: \(finalDataPlus.count)")
        print("每行列数: \(totalCols)")
    }
}

// MARK: - 扩展：提取失败信息
extension AtlasDataProcessor {
    func extractFailInfo() -> [[String: String]] {
        var failInfoList: [[String: String]] = []
        
        guard finalDataPlus.count > 4 else {
            return failInfoList
        }
        
        let headerRow = finalDataPlus[0]
        // print("Plus版标题行: \(headerRow)")
        guard let statusColIdx = headerRow.firstIndex(of: "Test Pass/Fail Status"),
              let failTestsColIdx = headerRow.firstIndex(of: "List of Failing Tests"),
              let filePathColIdx = headerRow.firstIndex(of: "file_path"),
              let endTimeColIdx = headerRow.firstIndex(of: "EndTime") else {
            print("警告：未找到必要的列名")
            return failInfoList
        }
        
        // 从第4行开始
        for i in 4..<finalDataPlus.count {
            let row = finalDataPlus[i]
            
            guard row.count > statusColIdx else { continue }
            
            if row[statusColIdx] == "FAIL" {
                let failInfo: [String: String] = [
                    "测试时间": row.count > endTimeColIdx ? row[endTimeColIdx] : "000000",
                    "文件路径": row.count > filePathColIdx ? row[filePathColIdx] : "未知文件路径",
                    "失败用例列表": row.count > failTestsColIdx ? row[failTestsColIdx] : "无具体失败用例"
                ]
                
                failInfoList.append(failInfo)
            }
        }
        
        return failInfoList
    }
}

// MARK: - 扩展：为 UI 提供便利方法
extension AtlasDataProcessor {
    
    // 获取时间戳（公开版本）
    func getTimestamp() -> String {
        return timestamp
    }
    
    // 获取最终数据
    func getFinalData() -> [[String]] {
        return finalData
    }
    
    // 获取最终数据 Plus 版本
    func getFinalDataPlus() -> [[String]] {
        return finalDataPlus
    }
    
    // 获取处理状态摘要
    func getProcessingSummary() -> [String: Any] {
        return [
            "files_processed": recordsFiles.count,
            "parameters_found": allParamNames.count,
            "failures_detected": extractFailInfo().count,
            "processing_timestamp": timestamp
        ]
    }
}

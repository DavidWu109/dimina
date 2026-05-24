//
//  DMPLog.swift
//  dimina
//
//  Dimina 引擎的统一日志门面。
//
//  使用方式:
//      DMPLog.app.info("launch start, appId=\(appId)")
//      DMPLog.scheme.error("resource not found: \(path)")
//
//  输出位置:
//      1. os_log: subsystem=com.echo.dimina, category=<channel>
//         可在 Console.app 或 `xcrun simctl spawn booted log show
//         --predicate 'subsystem == "com.echo.dimina"'` 中过滤。
//      2. 文件: Documents/dimina.log（同时含所有 channel，方便取走）
//

import Foundation
import os

public enum DMPLogChannel: String {
    case app      // DMPApp 生命周期
    case render   // DMPRender / WebView 渲染流程
    case bridge   // JSBridge invoke / publish
    case bundle   // 资源包加载、解压、版本
    case pool     // WebView 复用池
    case scheme   // 自定义 URLScheme 资源解析
}

public enum DMPLog {
    public static let subsystem = "com.echo.dimina"

    public enum Severity: Int, Comparable {
        case debug = 0
        case info  = 1
        case warn  = 2
        case error = 3

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        fileprivate var tag: String {
            switch self {
            case .debug: return "🟦 DEBUG"
            case .info:  return "🟩 INFO "
            case .warn:  return "🟧 WARN "
            case .error: return "🟥 ERROR"
            }
        }

        fileprivate var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info:  return .info
            case .warn:  return .default
            case .error: return .error
            }
        }
    }

    /// 最低输出级别。默认 .debug 以便排查问题；线上可改成 .info。
    public static var minimumLevel: Severity = .debug

    /// 是否落盘到 Documents/dimina.log。
    public static var persistToFile: Bool = true

    public static let app    = Channel(channel: .app)
    public static let render = Channel(channel: .render)
    public static let bridge = Channel(channel: .bridge)
    public static let bundle = Channel(channel: .bundle)
    public static let pool   = Channel(channel: .pool)
    public static let scheme = Channel(channel: .scheme)

    public struct Channel {
        let channel: DMPLogChannel
        private let osLog: OSLog

        init(channel: DMPLogChannel) {
            self.channel = channel
            self.osLog = OSLog(subsystem: DMPLog.subsystem, category: channel.rawValue)
        }

        public func debug(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
            emit(.debug, message(), file: file, line: line)
        }
        public func info(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
            emit(.info, message(), file: file, line: line)
        }
        public func warn(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
            emit(.warn, message(), file: file, line: line)
        }
        public func error(_ message: @autoclosure () -> String, file: String = #fileID, line: Int = #line) {
            emit(.error, message(), file: file, line: line)
        }

        private func emit(_ level: Severity, _ message: String, file: String, line: Int) {
            guard level >= DMPLog.minimumLevel else { return }
            let fileName = (file as NSString).lastPathComponent
            let body = "[\(channel.rawValue)] \(message) (\(fileName):\(line))"
            os_log("%{public}@", log: osLog, type: level.osLogType, body)
            if DMPLog.persistToFile {
                DMPLog.persist(level: level, channel: channel, message: message, file: fileName, line: line)
            }
        }
    }

    // MARK: - 落盘

    private static let fileQueue = DispatchQueue(label: "com.echo.dimina.log.file")

    public static var logFileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("dimina.log")
    }()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()

    fileprivate static func persist(level: Severity,
                                    channel: DMPLogChannel,
                                    message: String,
                                    file: String,
                                    line: Int) {
        let stamp = dateFormatter.string(from: Date())
        let entry = "\(stamp) \(level.tag) [\(channel.rawValue)] \(message) (\(file):\(line))\n"
        guard let data = entry.data(using: .utf8) else { return }
        let url = logFileURL
        fileQueue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// 清空 dimina.log。建议在每次小程序启动时调用，避免日志无限增长。
    public static func resetFile() {
        let url = logFileURL
        fileQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

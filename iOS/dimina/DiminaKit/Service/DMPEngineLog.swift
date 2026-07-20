//
//  DMPEngineLog.swift
//  dimina
//
//  Created by Lehem on 2025/4/16.
//

import Foundation
import JavaScriptCore

public enum LogLevel: Int {
    case log = 0
    case info = 1
    case warn = 2
    case error = 3
    
    var prefix: String {
        switch self {
        case .log: return "LOG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }
}

public class DMPEngineLog {
    
    public static func injectConsole(to context: JSContext) {
        let console = JSValue(newObjectIn: context)
        
        let consoleLog: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            printLog(.log, values: args)
        }

        let consoleInfo: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            printLog(.info, values: args)
        }

        let consoleWarn: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            printLog(.warn, values: args)
        }

        let consoleError: @convention(block) () -> Void = {
            let args = JSContext.currentArguments() as? [JSValue] ?? []
            printLog(.error, values: args)
        }
        
        console?.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console?.setObject(consoleInfo, forKeyedSubscript: "info" as NSString)
        console?.setObject(consoleWarn, forKeyedSubscript: "warn" as NSString)
        console?.setObject(consoleError, forKeyedSubscript: "error" as NSString)
        
        context.setObject(console!, forKeyedSubscript: "console" as NSString)
    }
    
    private static func printLog(_ level: LogLevel, values: [JSValue]) {
        let stringValues = values.map { formatJSValue($0) }
        let message = stringValues.joined(separator: " ")

        switch level {
        case .log, .info:
            DMPLogger.debug("[\(level.prefix)] \(message)")
            // 记录含关键字的 log
            if message.contains("DEBUG") || message.contains("getCommonConfig") || message.contains("error") || message.contains("request") {
                writeToLogFile("[\(level.prefix)] \(message)")
            }
        case .warn:
            DMPLogger.debug("⚠️ [\(level.prefix)] \(message)")
            writeToLogFile("⚠️ [\(level.prefix)] \(message)")
        case .error:
            DMPLogger.debug("❌ [\(level.prefix)] \(message)")
            writeToLogFile("❌ [\(level.prefix)] \(message)")
        }
    }

    public static func writeToLogFile(_ msg: String) {
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dimina_console.log")
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: logFile)
            }
        }
    }
    
    private static func formatJSValue(_ value: JSValue) -> String {
        if value.isNull || value.isUndefined {
            return value.isNull ? "null" : "undefined"
        } else if value.isString || value.isNumber || value.isBoolean {
            return value.toString()
        } else if value.isArray {
            guard let array = value.toArray() else { return "[]" }
            let formattedItems = array.compactMap { item -> String? in
                if let jsValue = item as? JSValue {
                    return formatJSValue(jsValue)
                }
                return "\(item)"
            }
            return "[\(formattedItems.joined(separator: ", "))]"
        } else if value.isObject {
            // Error 对象的 message/name/stack 是 non-enumerable，toDictionary() 会丢失。
            if let ctor = value.objectForKeyedSubscript("constructor"),
               let ctorName = ctor.objectForKeyedSubscript("name").toString(),
               ctorName.hasSuffix("Error") {
                let name = value.objectForKeyedSubscript("name").toString() ?? ctorName
                let message = value.objectForKeyedSubscript("message").toString() ?? ""
                let stack = value.objectForKeyedSubscript("stack").toString() ?? ""
                return "\(name): \(message)\n\(stack)"
            }
            if let dict = value.toDictionary(), !dict.isEmpty {
                do {
                    let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
                    if let jsonString = String(data: data, encoding: .utf8) {
                        return jsonString
                    }
                } catch {
                }
            }
            // 空字典或不可序列化时回退到 toString，并附 message 字段（若有）
            let fallback = value.toString() ?? "[Object]"
            if let msg = value.objectForKeyedSubscript("message")?.toString(), !msg.isEmpty, msg != "undefined" {
                return "\(fallback) message=\(msg)"
            }
            return fallback
        }

        return value.toString() ?? "Unknown"
    }
}




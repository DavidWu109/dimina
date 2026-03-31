//
//  DMPEngineParam.swift
//  dimina
//
//  Created by Lehem on 2025/5/16.
//

import Foundation
import JavaScriptCore

public enum DMPBridgeParamType: Int {
    case object = 0
    case array = 1
    case string = 2
    case number = 3
    case boolean = 4
    case float = 5
    case double = 6
    case null = 7
    case undefined = 8
}


public class DMPBridgeParam {
    public var value: Any
    public var type: DMPBridgeParamType
    public var isAsync: Bool = false
    
    public init(value: Any) {
        if value is [String: Any] {
            self.type = .object
            self.isAsync = true
        } else if value is [Any] {
            self.type = .array
        } else if value is String {
            self.type = .string
        } else if value is NSNumber {
            self.type = .number
        } else if value is Bool {
            self.type = .boolean
        } else if value is Float {
            self.type = .float
        } else if value is Double {
            self.type = .double
        } else {
            self.type = .null
        }

        self.value = value
    }

    public func getMap() -> DMPMap {
        if type != .object {
            return DMPMap()
        }
        return DMPMap(value as! [String: Any])
    }

    public func getValue() -> Any {
        return value
    }

    public func getType() -> DMPBridgeParamType {
        return type
    }

    public func getJSValue(context: JSContext) -> JSValue {
        switch type {
        case .object:
            return JSValue(object: value as! [String: Any], in: context)
        case .array:
            return JSValue(object: value as! [Any], in: context)
        case .string:
            return JSValue(object: value as! String, in: context)
        case .number:
            return JSValue(object: value as! NSNumber, in: context)
        case .boolean:
            return JSValue(object: value as! Bool, in: context)
        case .float:
            return JSValue(object: value as! Float, in: context)
        case .double:
            return JSValue(object: value as! Double, in: context)
        case .null:
            return JSValue(nullIn: context)
        case .undefined:
            return JSValue(undefinedIn: context)
        }
    }
}

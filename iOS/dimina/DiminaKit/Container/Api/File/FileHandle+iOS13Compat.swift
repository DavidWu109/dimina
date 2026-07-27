//
//  FileHandle+iOS13Compat.swift
//  dimina
//
//  Compatibility wrappers for throwing FileHandle APIs introduced in iOS 13.4.
//

import Foundation

extension FileHandle {

    @discardableResult
    func compatSeekToEnd() throws -> UInt64 {
        if #available(iOS 13.4, *) {
            return try seekToEnd()
        }
        return seekToEndOfFile()
    }

    func compatClose() throws {
        if #available(iOS 13.4, *) {
            try close()
        } else {
            closeFile()
        }
    }

    func compatTruncate(atOffset offset: UInt64) throws {
        if #available(iOS 13.4, *) {
            try truncate(atOffset: offset)
        } else {
            truncateFile(atOffset: offset)
        }
    }

    func compatSeek(toOffset offset: UInt64) throws {
        if #available(iOS 13.4, *) {
            try seek(toOffset: offset)
        } else {
            seek(toFileOffset: offset)
        }
    }

    func compatRead(upToCount count: Int) throws -> Data? {
        if #available(iOS 13.4, *) {
            return try read(upToCount: count)
        }
        return readData(ofLength: count)
    }
}

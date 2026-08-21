//
//  LocalStore.swift
//  CloudCrown
//
//  Atomic JSON persistence in Application Support. One file per collection.
//  A local draft survives without an account; sync would layer on top.
//

import Foundation

protocol LocalStoring {
    func load<T: Decodable>(_ type: T.Type, from file: StoreFile) throws -> T?
    func save<T: Encodable>(_ value: T, to file: StoreFile) throws
    func delete(_ file: StoreFile) throws
    func deleteAll() throws
    func exportBundle() throws -> Data
}

enum StoreFile: String, CaseIterable {
    case settings
    case profile
    case activities
    case places
    case plans
    case alerts
    case alertEvents
    case feedback
    case history
    case snapshots
    case drafts

    var filename: String { "\(rawValue).json" }
}

enum StoreError: LocalizedError {
    case directoryUnavailable
    case encodingFailed(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .directoryUnavailable: return "Local storage is unavailable on this device."
        case .encodingFailed(let d): return "Could not write local data: \(d)"
        case .decodingFailed(let d): return "Could not read local data: \(d)"
        }
    }
}

final class LocalStore: LocalStoring {

    private let directory: URL
    private let queue = DispatchQueue(label: "app.CloudCrown.store", qos: .userInitiated)

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(directoryName: String = "CloudCrownData") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for file: StoreFile) -> URL {
        directory.appendingPathComponent(file.filename)
    }

    func load<T: Decodable>(_ type: T.Type, from file: StoreFile) throws -> T? {
        try queue.sync {
            let url = self.url(for: file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            do {
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else { return nil }
                return try decoder.decode(T.self, from: data)
            } catch let error as DecodingError {
                throw StoreError.decodingFailed(String(describing: error))
            }
        }
    }

    func save<T: Encodable>(_ value: T, to file: StoreFile) throws {
        try queue.sync {
            do {
                let data = try encoder.encode(value)
                // Atomic write so a crash mid-save cannot corrupt existing data.
                try data.write(to: url(for: file), options: .atomic)
            } catch let error as EncodingError {
                throw StoreError.encodingFailed(String(describing: error))
            }
        }
    }

    func delete(_ file: StoreFile) throws {
        try queue.sync {
            let url = self.url(for: file)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    func deleteAll() throws {
        for file in StoreFile.allCases { try delete(file) }
    }

    /// Produces a single JSON document containing every stored collection.
    func exportBundle() throws -> Data {
        try queue.sync {
            var payload: [String: Any] = [
                "app": "CloudCrown",
                "exportedAt": ISO8601DateFormatter().string(from: Date()),
                "schemaVersion": 1
            ]
            for file in StoreFile.allCases where file != .drafts {
                let url = self.url(for: file)
                guard FileManager.default.fileExists(atPath: url.path),
                      let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) else { continue }
                payload[file.rawValue] = json
            }
            return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        }
    }
}

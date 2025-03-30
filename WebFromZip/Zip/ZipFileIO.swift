//
//  ZipFileIO.swift
//  WebFromZip
//
//  Created by Randy on 3/24/25.
//

import Foundation
import CryptoKit

import Hummingbird
import HummingbirdCore
import Logging
import NIOCore
import NIOPosix

public struct ZipEntry : Sendable{
	let offset: UInt64
	let length: UInt64
}

public struct RegexEntry : Sendable {
	let regex: NSRegularExpression
	let replacement: String

	/// Initialize RegexEntry
	/// - Parameters:
	///   - pattern: Pattern to match
	///   - replacement: Replacement string
	public init(pattern: String, replacement: String) {
		self.regex = try! NSRegularExpression(pattern: pattern, options: [])
		self.replacement = replacement
	}
}

extension Notification.Name {
	static let zipServerIndexing = Notification.Name("zipServerIndexing")
}

extension NSRegularExpression {
	func stringByReplacingMatches(
		in string: String,
		withTemplate templ: String
	) -> String {
		return self.stringByReplacingMatches(
			in: string,
			options: [],
			range: NSRange(location: 0, length: string.utf16.count),
			withTemplate: templ)
	}
}

/// Manages File reading and writing.
public struct ZipFileIO: Sendable {
	let fileIO: NonBlockingFileIO
	let logger: Logger
	var lookup: [String: ZipEntry] = [:]
	var zipArchivePath: String = ""
	
	static var regexList: [RegexEntry] = []
	
	static public func addRegexEntry(pattern: String, replacement: String) {
		self.regexList.append(RegexEntry(pattern: pattern, replacement: replacement))
	}

	/// Initialize ZipFileIO
	///   - zipArchivePath: Root folder to serve files from
	///   - threadPool: Thread pool used when loading files
	public init(zipArchivePath: String, threadPool: NIOThreadPool, logger: Logger) {
		self.fileIO = .init(threadPool: threadPool)
		self.logger = logger
		setArchivePath(path: zipArchivePath)
	}

	/// Remove preceding slash
	///
	/// - Parameters:
	///   - path: archive file path
	/// - Returns: string without initial slash
	public mutating func setArchivePath(path: String) {
		self.zipArchivePath = path
				
		do {
			let indexPath = self.zipArchivePath.replacingOccurrences(of: ".zip", with: ".idx")
			if FileManager.default.fileExists(atPath: indexPath) {
				logger.info("Reading index file")
				self.lookup = [:]
				let size64 = MemoryLayout<UInt64>.size
				let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))
				var offset = 0
				while offset < data.count {
					let keyLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
					offset += MemoryLayout<UInt32>.size
					let keyData = data.subdata(in: offset..<(offset + Int(keyLength)))
					let key = String(data: keyData, encoding: .utf8)!
					offset += Int(keyLength)
					if offset % size64 != 0 {
						let padding = size64 - (offset % size64)
						offset += padding
					}
					let entryOffset = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt64.self) }
					offset += size64
					let entryLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt64.self) }
					offset += size64
					self.lookup[key] = ZipEntry(offset: entryOffset, length: entryLength)
				}
				logger.info("Index contains \(self.lookup.count) file entries")
			}
			else {
				logger.info("Reading from archive")

				NotificationCenter.default.post(name: .zipServerIndexing, object: nil)

				let zipArchiveURL = URL(fileURLWithPath: self.zipArchivePath)
				let zipArchive = try Archive(url: zipArchiveURL, accessMode: .read)
				
				lookup = [:]
				
				let dir = zipArchive.makeIterator()
				for entry in dir {
					if !entry.isCompressed {
						let name = entry.path
						let offset = entry.dataOffset
						let length = entry.uncompressedSize
						self.lookup[name] = ZipEntry(offset: offset, length: length)
					}
				}
				logger.info("Archive contains \(self.lookup.count) files")

				// Serialize lookup dictionary to a compact binary format and write to indexPath
				logger.info("Writing index file")
				let size64 = MemoryLayout<UInt64>.size
				var binaryData = Data()
				var offset = 0
				for (key, value) in self.lookup {
					if let keyData = key.data(using: .utf8) {
						var keyLength = UInt32(keyData.count)
						binaryData.append(Data(bytes: &keyLength, count: MemoryLayout<UInt32>.size))
						binaryData.append(keyData)
						offset += MemoryLayout<UInt32>.size + keyData.count
						if offset % size64 != 0 {
							let padding = size64 - (offset % size64)
							binaryData.append(Data(count: padding))
							offset += padding
						}
						var offset = value.offset
						var length = value.length
						binaryData.append(Data(bytes: &offset, count: size64))
						binaryData.append(Data(bytes: &length, count: size64))
					}
				}
				try binaryData.write(to: URL(fileURLWithPath: indexPath))
			}
		} catch {
			logger.info("Failed to initialize zip archive: \(error)")
		}
	}
	
	/// Get the archive file count
	///
	/// - Parameters:
	public func archiveFileCount() -> Int {
		return self.lookup.count
	}
	
	/// Set the archive path and scan for entries
	///
	/// - Parameters:
	///   - path: archive file path
	func removeInitialSlash(path: String) -> String {
		return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
	}
	
	/// Get Entry for path
	///
	/// - Parameters:
	///   - path: archive file path
	/// - Returns: Entry
	public func entryForPath(_ path: String) -> ZipEntry? {
		var path = removeInitialSlash(path: path)

		if let entry = self.lookup[path] {
			return entry
		}

		for regexEntry in ZipFileIO.regexList {
			path = regexEntry.regex.stringByReplacingMatches(in: path, withTemplate: regexEntry.replacement)
			if let entry = self.lookup[path] {
				return entry
			}
		}

		return nil
	}

	/// Get the size of a file in the archive
	///
	/// - Parameters:
	///   - path: archive file path
	/// - Returns: file size
	public func fileSize(path: String) -> UInt64 {
		if let entry = entryForPath(path) {
			return entry.length
		}
		return 0
	}

	/// Load file and return response body
	///
	/// Depending on the file size this will return either a response body containing a ByteBuffer or a stream that will provide the
	/// file in chunks.
	/// - Parameters:
	///   - path: System file path
	///   - context: Context this request is being called in
	///   - chunkLength: Size of the chunks read from disk and loaded into memory (in bytes). Defaults to the value suggested by `swift-nio`.
	/// - Returns: Response body
	public func loadFile(
		path: String,
		context: some RequestContext,
		chunkLength: Int = NonBlockingFileIO.defaultChunkSize
	) async throws -> ResponseBody {
		guard let entry = entryForPath(path) else {
			throw HTTPError(.notFound)
		}
		if entry.length == 0 {
			return ResponseBody(contentLength: 0) { writer in
				try await writer.finish(nil)
			}
		}
		let zipRange: ClosedRange<UInt64> = entry.offset...(entry.offset+entry.length-1)
		return self.readFile(range: zipRange, context: context, chunkLength: chunkLength)
	}

	/// Load part of file and return response body.
	///
	/// Depending on the size of the part this will return either a response body containing a ByteBuffer or a stream that will provide the
	/// file in chunks.
	/// - Parameters:
	///   - path: System file path
	///   - range:Range defining how much of the file is to be loaded
	///   - context: Context this request is being called in
	///   - chunkLength: Size of the chunks read from disk and loaded into memory (in bytes). Defaults to the value suggested by `swift-nio`.
	/// - Returns: Response body plus file size
	public func loadFile(
		path: String,
		range: ClosedRange<Int>,
		context: some RequestContext,
		chunkLength: Int = NonBlockingFileIO.defaultChunkSize
	) async throws -> ResponseBody {
		guard let entry = entryForPath(path) else {
			throw HTTPError(.notFound)
		}
		if entry.length == 0 {
			return ResponseBody(contentLength: 0) { writer in
				try await writer.finish(nil)
			}
		}
		let dataOffset = entry.offset
		let dataSize = entry.length
		var range64: ClosedRange<UInt64> = dataOffset+UInt64(range.lowerBound)...dataOffset+UInt64(range.upperBound)
		let fileRange: ClosedRange<UInt64> = dataOffset...dataOffset+dataSize - 1
		range64 = range64.clamped(to: fileRange)
		return self.readFile(range: range64, context: context, chunkLength: chunkLength)
	}

	/// Return response body that will read file
	func readFile(
		range: ClosedRange<UInt64>,
		context: some RequestContext,
		chunkLength: Int = NonBlockingFileIO.defaultChunkSize
	) -> ResponseBody {
		ResponseBody(contentLength: range.count) { writer in
			try await self.fileIO.withFileHandle(path: zipArchivePath, mode: .read) { handle in
				let endOffset = range.endIndex
				let chunkLength = chunkLength
				var fileOffset = range.startIndex
				let allocator = ByteBufferAllocator()

				while case .inRange(let offset) = fileOffset {
					let bytesLeft = range.distance(from: fileOffset, to: endOffset)
					let bytesToRead = Swift.min(chunkLength, bytesLeft)
					let buffer = try await self.fileIO.read(
						fileHandle: handle,
						fromOffset: numericCast(offset),
						byteCount: bytesToRead,
						allocator: allocator
					)
					fileOffset = range.index(fileOffset, offsetBy: bytesToRead)
					try await writer.write(buffer)
				}
				try await writer.finish(nil)
			}
		}
	}
}

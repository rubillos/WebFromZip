//
//  ZipFileIO.swift
//  RickAndRandy
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

/// Manages File reading and writing.
public struct ZipFileIO: Sendable {
	let fileIO: NonBlockingFileIO
	let logger: Logger
	var lookup: [String: ZipEntry] = [:]
	var zipArchivePath: String = ""

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
//					logger.info("Entry: \(name) - off: \(offset) - len: \(length)")
				}
			}
			logger.info("Archive contains \(self.lookup.count) files")
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
		let regex = try! NSRegularExpression(pattern: "@\\d+x", options: [])
		let range = NSRange(location: 0, length: path.utf16.count)
		path = regex.stringByReplacingMatches(in: path, options: [], range: range, withTemplate: "")
		path = path.replacingOccurrences(of: "360", with: "-1080").replacingOccurrences(of: "-540", with: "-1080").replacingOccurrences(of: "-2160", with: "-1080")
		guard let entry = self.lookup[path] else {
			path = path.replacingOccurrences(of: ".m4v", with: "-HEVC.m4v")
			return self.lookup[path]
		}
		return entry
	}

	/// Get the size of a file in the archive
	///
	/// - Parameters:
	///   - path: archive file path
	/// - Returns: file size
	public func fileSize(path: String) -> UInt64 {
		guard let entry = entryForPath(path) else {
			return 0
		}
		return entry.length
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

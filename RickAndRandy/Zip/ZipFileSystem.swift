//
//  ZipFileSystem.swift
//  RickAndRandy
//
//  Created by Randy on 3/24/25.
//

import Foundation
import Hummingbird
import Logging
import NIOPosix

/// Local file system file provider used by FileMiddleware. All file accesses are relative to a root folder
public struct ZipFileSystem: FileProvider {
	/// File attributes required by ``FileMiddleware``
	public struct FileAttributes: Sendable, FileMiddlewareFileAttributes {
		/// Is file a folder
		public let isFolder: Bool
		/// Size of file
		public let size: Int
		/// Last time file was modified
		public let modificationDate: Date

		/// Initialize FileAttributes
		init(isFolder: Bool, size: Int, modificationDate: Date) {
			self.isFolder = isFolder
			self.size = size
			self.modificationDate = modificationDate
		}
	}

	/// File Identifier (Fully qualified path)
	public typealias FileIdentifier = String

	let zipFileIO: ZipFileIO

	/// Initialize LocalFileSystem FileProvider
	/// - Parameters:
	///   - zipArchivePath: Root folder to serve files from
	///   - threadPool: Thread pool used when loading files
	///   - logger: Logger to output root folder information
	public init(zipArchivePath: String, threadPool: NIOThreadPool, logger: Logger) {
		self.zipFileIO = .init(zipArchivePath: zipArchivePath, threadPool: threadPool, logger: logger)
	}

	/// Get full path name with local file system root prefixed
	/// - Parameter path: path from URI
	/// - Returns: Full path
	public func getFileIdentifier(_ path: String) -> FileIdentifier? {
		return path
	}

	/// Get file attributes
	/// - Parameter path: FileIdentifier
	/// - Returns: File attributes
	public func getAttributes(id path: FileIdentifier) async throws -> FileAttributes? {
		return .init(
			isFolder: false,
			size: Int(self.zipFileIO.fileSize(path: path)),
			modificationDate: Date(timeIntervalSince1970: 0)
		)
	}

	/// Return a reponse body that will write the file body
	/// - Parameters:
	///   - path: FileIdentifier
	///   - context: Request context
	/// - Returns: Response body
	public func loadFile(id path: FileIdentifier, context: some RequestContext) async throws -> ResponseBody {
		try await self.zipFileIO.loadFile(path: path, context: context)
	}

	/// Return a reponse body that will write a partial file body
	/// - Parameters:
	///   - path: FileIdentifier
	///   - range: Part of file to return
	///   - context: Request context
	/// - Returns: Response body
	public func loadFile(id path: FileIdentifier, range: ClosedRange<Int>, context: some RequestContext) async throws -> ResponseBody {
		try await self.zipFileIO.loadFile(path: path, range: range, context: context)
	}
}

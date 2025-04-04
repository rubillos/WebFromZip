//
//  ZipMiddleWare.swift
//  WebFromZip
//
//  Created by Randy on 3/24/25.
//

import Foundation
import HTTPTypes
import HummingbirdCore
import Hummingbird
import Logging
import NIOCore
import NIOPosix

/// Middleware for serving static files.
///
/// If router returns a 404 ie a route was not found then this middleware will treat the request
/// path as a filename relative to a defined rootFolder (this defaults to "public"). It checks to see if
/// a file exists there and if so the file contents are passed back in the response.
///
/// The file middleware supports both HEAD and GET methods and supports parsing of
/// "if-modified-since", "if-none-match", "if-range" and 'range" headers. It will output "content-length",
/// "modified-date", "eTag", "content-type", "cache-control" and "content-range" headers where
/// they are relevant.
public struct ZipMiddleware<Context: RequestContext, Provider: FileProvider>: RouterMiddleware
where Provider.FileAttributes: FileMiddlewareFileAttributes {
	let cacheControl: CacheControl
	let searchForIndexHtml: Bool
	let urlBasePath: String?
	let fileProvider: Provider
	let mediaTypeFileExtensionMap: [MediaType.FileExtension: MediaType]

	/// Create ZipMiddleware
	/// - Parameters:
	///   - zipArchivePath: Root folder to look for files
	///   - urlBasePath: Prefix to remove from request URL
	///   - cacheControl: What cache control headers to include in response
	///   - searchForIndexHtml: Should we look for index.html in folders
	///   - threadPool: ThreadPool used by file loading
	///   - logger: Logger used to output file information
	public init(
		_ zipArchivePath: String = "public",
		urlBasePath: String? = nil,
		cacheControl: CacheControl = .init([]),
		searchForIndexHtml: Bool = false,
		threadPool: NIOThreadPool = NIOThreadPool.singleton,
		logger: Logger = Logger(label: "ZipMiddleware")
	) where Provider == ZipFileSystem {
		self.init(
			fileProvider: ZipFileSystem(
				zipArchivePath: zipArchivePath,
				threadPool: threadPool,
				logger: logger
			),
			urlBasePath: urlBasePath,
			cacheControl: cacheControl,
			searchForIndexHtml: searchForIndexHtml,
			mediaTypeFileExtensionMap: [:]
		)
	}

	/// Create ZipMiddleware using custom ``FileProvider``.
	/// - Parameters:
	///   - fileProvider: File provider
	///   - urlBasePath: Prefix to remove from request URL
	///   - cacheControl: What cache control headers to include in response
	///   - searchForIndexHtml: Should we look for index.html in folders
	public init(
		fileProvider: Provider,
		urlBasePath: String? = nil,
		cacheControl: CacheControl = .init([]),
		searchForIndexHtml: Bool = false
	) {
		self.init(
			fileProvider: fileProvider,
			urlBasePath: urlBasePath,
			cacheControl: cacheControl,
			searchForIndexHtml: searchForIndexHtml,
			mediaTypeFileExtensionMap: [:]
		)
	}

	private init(
		fileProvider: Provider,
		urlBasePath: String? = nil,
		cacheControl: CacheControl = .init([]),
		searchForIndexHtml: Bool = false,
		mediaTypeFileExtensionMap: [MediaType.FileExtension: MediaType]
	) {
		self.cacheControl = cacheControl
		self.searchForIndexHtml = searchForIndexHtml
		self.urlBasePath = urlBasePath.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
		self.fileProvider = fileProvider
		self.mediaTypeFileExtensionMap = mediaTypeFileExtensionMap
	}

	/// Handle request
	public func handle(_ request: Request, context: Context, next: (Request, Context) async throws -> Response) async throws -> Response {
		do {
			return try await next(request, context)
		} catch {
			// Guard that error is HTTP error notFound
			guard let httpError = error as? HTTPResponseError, httpError.status == .notFound else {
				throw error
			}

			guard request.method == .get || request.method == .head else {
				throw error
			}

			// Remove percent encoding from URI path
			guard var path = request.uri.path.removingPercentEncoding else {
				throw HTTPError(.badRequest, message: "Invalid percent encoding in URL")
			}

			// file paths that contain ".." are considered illegal
			guard !path.contains("..") else {
				throw HTTPError(.badRequest)
			}

			// Do we have a prefix to remove from the path
			if let urlBasePath {
				// If path doesnt have prefix then throw error
				guard path.hasPrefix(urlBasePath) else {
					throw error
				}
				let subPath = path.dropFirst(urlBasePath.count)
				if subPath.first == nil {
					path = "/"
				} else if subPath.first == "/" {
					path = String(subPath)
				} else {
					// If first character isn't a "/" then the base path isn't a complete folder name
					// in this situation, so isn't inside the specified folder
					throw error
				}
			}
			// get file attributes and actual file path and ID (It might be an index.html)
			let (actualPath, actualID, attributes) = try await self.getFileAttributes(path)
			// we have a file so indicate it came from the ZipMiddleware
			context.coreContext.endpointPath.value = "ZipMiddleware"
			// get how we should respond
			let fileResult = try await self.constructResponse(path: actualPath, attributes: attributes, request: request)

			switch fileResult {
			case .notModified(let headers):
				return Response(status: .notModified, headers: headers)
			case .loadFile(let headers, let range):
				switch request.method {
				case .get:
					if let range {
						let body = try await self.fileProvider.loadFile(id: actualID, range: range, context: context)
						return Response(status: .partialContent, headers: headers, body: body)
					}

					let body = try await self.fileProvider.loadFile(id: actualID, context: context)
					return Response(status: .ok, headers: headers, body: body)

				case .head:
					return Response(status: .ok, headers: headers, body: .init())

				default:
					throw error
				}
			}
		}
	}
}

extension ZipMiddleware {
	/// Whether to return data from the file or a not modified response
	private enum FileResult {
		case notModified(HTTPFields)
		case loadFile(HTTPFields, ClosedRange<Int>?)
	}

	/// Return file attributes, and actual file path
	private func getFileAttributes(_ path: String) async throws -> (path: String, id: Provider.FileIdentifier, attributes: Provider.FileAttributes) {
		guard let id = self.fileProvider.getFileIdentifier(path),
			let attributes = try await self.fileProvider.getAttributes(id: id)
		else {
			throw HTTPError(.notFound)
		}
		// if file is a directory seach and `searchForIndexHtml` is set to true
		// then search for index.html in directory
		if attributes.isFolder {
			guard self.searchForIndexHtml else { throw HTTPError(.notFound) }
			let indexPath = self.appendingPathComponent(path, "index.html")
			guard let indexID = self.fileProvider.getFileIdentifier(indexPath),
				let indexAttributes = try await self.fileProvider.getAttributes(id: indexID)
			else {
				throw HTTPError(.notFound)
			}
			return (path: indexPath, id: indexID, attributes: indexAttributes)
		} else {
			return (path: path, id: id, attributes: attributes)
		}
	}

	/// Parse request headers and generate response headers
	private func constructResponse(path: String, attributes: Provider.FileAttributes, request: Request) async throws -> FileResult {
		let eTag = self.createETag([
			String(describing: attributes.modificationDate.timeIntervalSince1970),
			String(describing: attributes.size),
		])

		// construct headers
		var headers = HTTPFields()

		// content-length
		headers[.contentLength] = String(describing: attributes.size)
		// modified-date
		let modificationDateString = self.formatDateForHTTPHeader(attributes.modificationDate)
		headers[.lastModified] = modificationDateString
		// eTag (constructed from modification date and content size)
		headers[.eTag] = eTag

		// content-type
		if let ext = self.fileExtension(for: path) {
			if let contentType = mediaTypeFileExtensionMap[ext] ?? MediaType.getMediaType(forExtension: ext) {
				headers[.contentType] = contentType.description
			}
		}

		headers[.acceptRanges] = "bytes"

		// cache-control
		if let cacheControlValue = self.cacheControl.getCacheControlHeader(for: path) {
			headers[.cacheControl] = cacheControlValue
		}

		if let rangeHeader = request.headers[.range] {
			guard let range = getRangeFromHeaderValue(rangeHeader) else {
				throw HTTPError(.rangeNotSatisfiable, message: "Unable to read range requested from file")
			}
			// range request conditional on etag or modified date being equal to value in if-range
			if let ifRange = request.headers[.ifRange], ifRange != headers[.eTag], ifRange != headers[.lastModified] {
				// do nothing and drop down to returning full file
			} else {
				let lowerBound = max(range.lowerBound, 0)
				let upperBound = min(range.upperBound, attributes.size - 1)
				headers[.contentRange] = "bytes \(lowerBound)-\(upperBound)/\(attributes.size)"
				// override content-length set above
				headers[.contentLength] = String(describing: upperBound - lowerBound + 1)
				return .loadFile(headers, range)
			}
		}
		return .loadFile(headers, nil)
	}

	private func formatDateForHTTPHeader(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		return formatter.string(from: date)
	}

	/// Convert "bytes=value-value" range header into `ClosedRange<Int>`
	///
	/// Also supports open ended ranges
	private func getRangeFromHeaderValue(_ header: String) -> ClosedRange<Int>? {
		do {
			var parser = ZipParser(header)
			guard try parser.read("bytes=") else { return nil }
			let lower = parser.read { $0.properties.numericType == .decimal }.string
			guard try parser.read("-") else { return nil }
			let upper = parser.read { $0.properties.numericType == .decimal }.string

			if lower == "" {
				guard let upperBound = Int(upper) else { return nil }
				return 0...upperBound
			} else if upper == "" {
				guard let lowerBound = Int(lower) else { return nil }
				return lowerBound...Int.max
			} else {
				guard let lowerBound = Int(lower),
					let upperBound = Int(upper)
				else { return nil }
				return lowerBound...upperBound
			}
		} catch {
			return nil
		}
	}

	private func createETag(_ strings: [String]) -> String {
		let string = strings.joined(separator: "-")
		let buffer = [UInt8](unsafeUninitializedCapacity: 16) { bytes, size in
			var index = 0
			for i in 0..<16 {
				bytes[i] = 0
			}
			for c in string.utf8 {
				bytes[index] ^= c
				index += 1
				if index == 16 {
					index = 0
				}
			}
			size = 16
		}

		return "W/\"\(buffer.map { String(format: "%02x", $0) }.joined())\""
	}

	private func appendingPathComponent(_ root: String, _ component: String) -> String {
		if root.last == "/" {
			return "\(root)\(component)"
		} else {
			return "\(root)/\(component)"
		}
	}

	private func fileExtension(for path: String) -> MediaType.FileExtension? {
		if let extPointIndex = path.lastIndex(of: ".") {
			let extIndex = path.index(after: extPointIndex)
			return .init(path.suffix(from: extIndex))
		}
		return nil
	}
}

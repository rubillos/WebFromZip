//
//  ZipServer.swift
//  RickAndRandy
//
//  Created by Randy on 3/22/25.
//

import Foundation
import Hummingbird
import Logging

struct ZipServer {
	static func run() async throws {
		let logger = Logger(label: "swift-web")
		let router = Router()
		
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		if let path = paths.first?.path{
			print("iTunes File Sharing folder path: \(path)")
		} else {
			print("Unable to find iTunes File Sharing folder path")
		}
		
		//		let zipName = "RickAndRandy.zip"
		//		let bundlePath = Bundle.main.bundlePath + "/" + zipName
		let bundlePath = "/Users/randy/Sites/RickAndRandy.zip"
		print("Bundle path: \(bundlePath)")
		
		//		router.add(middleware: FileMiddleware("/Users/randy/Sites/PortlandAve-Mobile", searchForIndexHtml: true))
		router.add(middleware: ZipMiddleware(bundlePath, logger: logger))
		//		router.add(middleware: LogRequestsMiddleware(.info))
		
		let app = Application(
			router: router,
			configuration: .init(address: .hostname("127.0.0.1", port: 8080)),
			logger: logger
		)
		
		print("Server started")
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
			NotificationCenter.default.post(name: .serverStarted, object: nil)
		}
		
		// Start the ZipServer
		try await app.runService()
	}
}

extension Notification.Name {
	static let serverStarted = Notification.Name("serverStarted")
}

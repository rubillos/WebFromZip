//
//  ZipServer.swift
//  RickAndRandy
//
//  Created by Randy on 3/22/25.
//

import Foundation
import Hummingbird
import Logging

extension Notification.Name {
	static let zipServerStarted = Notification.Name("zipServerStarted")
}

struct ZipServer {
	static func run(_ bundlePath: String) async throws {
		let logger = Logger(label: "swift-web")
		let router = Router()
		
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
			NotificationCenter.default.post(name: .zipServerStarted, object: nil)
		}
		
		// Start the ZipServer
		try await app.runService()
	}
}

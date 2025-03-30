//
//  ZipServer.swift
//  WebFromZip
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
	static var zipMiddle: (any MiddlewareProtocol<Request, Response, BasicRequestContext>)? = nil
	static var router: Router<BasicRequestContext>? = nil
	static var logger: Logger? = nil
	static var serverTask: Task<Void, Never>? = nil
	
	static func run(_ bundlePath: String? = nil) {
		if self.router == nil && bundlePath != nil {
			Task {
				self.logger = Logger(label: "swift-web")
				self.router = Router()
				self.zipMiddle = ZipMiddleware(bundlePath!, logger: self.logger!)
				self.router?.add(middleware: self.zipMiddle!)
				start()
			}
		}
		else {
			start()
		}
	}

	static func start() {
		if self.router != nil && self.serverTask == nil {
			let app = Application(
				router: self.router!,
				configuration: .init(address: .hostname("127.0.0.1", port: 8080)),
				logger: self.logger
			)
			
			print("Server started")
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				NotificationCenter.default.post(name: .zipServerStarted, object: nil)
			}
			self.serverTask = Task {
				do {
					try await app.runService()
					print("Server finished")
				} catch {
					print("Failed to start server: \(error)")
				}
			}
		}
	}
	
	static func stop() {
		if self.serverTask != nil {
			print("Stopping server")
			self.serverTask?.cancel()
			self.serverTask = nil
		}
	}
}

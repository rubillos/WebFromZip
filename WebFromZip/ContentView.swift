//
//  ContentView.swift
//  WebFromZip
//
//  Created by Randy on 3/29/25.
//

import SwiftUI
@preconcurrency import WebKit
import Foundation

struct WebView: UIViewRepresentable {
	@Binding var webView: WKWebView
	let url: URL

	func makeUIView(context: Context) -> WKWebView {
		webView.navigationDelegate = context.coordinator
		return webView
	}
	
	func updateUIView(_ uiView: WKWebView, context: Context) {
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
		var parent: WebView

		init(_ parent: WebView) {
			self.parent = parent
		}

		func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
			if let url = navigationAction.request.url {
				let urlString = url.absoluteString
				var newURLString = urlString
				
				// Redirect URLs from main web URL to localhost
				newURLString = newURLString.replacingOccurrences(of: Constants.mainWebURLwww, with: Constants.localhost)
				newURLString = newURLString.replacingOccurrences(of: Constants.mainWebURL, with: Constants.localhost)
				
				// Redirect https to http if redirecting from the main web URL
				if urlString != newURLString {
					newURLString = newURLString.replacingOccurrences(of: Constants.httpsScheme, with: Constants.httpScheme)
				}
				
				// For localhost URLs, add default index if it ends with a slash
				if newURLString.contains(Constants.localhost) && newURLString.hasSuffix(Constants.slashChar) {
					newURLString += Constants.defaultIndex
				}
					
				if urlString != newURLString {
					if let modifiedURL = URL(string: newURLString) {
						print("Original URL: \(url)")
						print("Modified URL: \(modifiedURL)")
						decisionHandler(.cancel)
						webView.load(URLRequest(url: modifiedURL))
						return
					}
				}
			}
			decisionHandler(.allow)
		}
	}
}

struct ContentView: View {
	@State private var webView = WKWebView()
	@State private var canGoBack = false
	@State private var canGoHome = false
	@State private var canGoForward = false
	@State private var showProgressView = true
	@State private var isIndexing = false
	@State private var errorMsg = ""
	@State private var orientation = UIDeviceOrientation.portrait

	let u = URL(string:Constants.homePage)
	
	var body: some View {
		Group {
			if orientation == .landscapeLeft {
				HStack(spacing: 0) {
					webViewContent
					controls
				}
				.ignoresSafeArea(edges: [.trailing, .bottom])
			} else if orientation == .landscapeRight {
				HStack(spacing: 0) {
					controls
					webViewContent
				}
				.ignoresSafeArea(edges: [.leading, .bottom])
			} else {
				VStack(spacing: 0) {
					webViewContent
					controls
				}
				.ignoresSafeArea(edges: .bottom)
			}
		}
		.onAppear {
			NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { _ in
				let current = UIDevice.current.orientation
				if current != self.orientation && (current == .portrait || current == .landscapeLeft || current == .landscapeRight) {
					self.orientation = UIDevice.current.orientation
				}
			}
			UIDevice.current.beginGeneratingDeviceOrientationNotifications()
			NotificationCenter.default.addObserver(forName: .zipServerIndexing, object: nil, queue: .main) { _ in
				self.isIndexing = true
				print("Notification: Indexing...")
			}
			NotificationCenter.default.addObserver(forName: .zipServerStarted, object: nil, queue: .main) { _ in
				if !self.canGoHome {
					self.canGoHome = true
					self.goHome()
				}
			}

			for pathRegex in Constants.pathRegexes {
				ZipFileIO.addRegexEntry(pattern: pathRegex[0], replacement: pathRegex[1])
			}

			startServer()

			NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
				ZipServer.stop()
			}
			NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
				ZipServer.run()
			}
		}
		.onDisappear {
			UIDevice.current.endGeneratingDeviceOrientationNotifications()
			NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
			NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
		}
	}

	var webViewContent: some View {
		ZStack {
			WebView(webView: $webView, url: u!)
				.onReceive(webView.publisher(for: \.canGoBack)) { canGoBack in
					self.canGoBack = canGoBack
				}
				.onReceive(webView.publisher(for: \.canGoForward)) { canGoForward in
					self.canGoForward = canGoForward
				}
			if showProgressView && errorMsg == "" {
				VStack {
					ProgressView()
						.progressViewStyle(CircularProgressViewStyle(tint: .black))
						.scaleEffect(2)
						.padding(20)

					if isIndexing {
						Text("Indexing...")
							.font(.title)
							.foregroundColor(.black)
					}
				}
			}
			if errorMsg != "" {
				VStack {
					Text(errorMsg)
						.font(.title)
						.foregroundColor(.black)
						.multilineTextAlignment(.center)
					
					Button(action: {
						startServer()
					}) {
						Text("Retry")
					}
					.font(.title)
					.padding([.top, .bottom], 10)
					.padding([.leading, .trailing], 20)
					.background(Color.blue)
					.foregroundColor(.white)
					.padding(.top, 25)
				}
			}
		}
	}

	struct ButtonLabels {
		static let back = "◀︎"
		static let home = "⌂"
		static let forward = "▶︎"
	}

	var controls: some View {
		Group {
			if orientation.isPortrait {
				HStack(spacing: 40) {
					Spacer()
					
					Button(action: {
						if webView.canGoBack {
							webView.goBack()
						}
					}) {
						Text(ButtonLabels.back)
					}
					.disabled(!canGoBack)
					
					Button(action: {
						goHome()
					}) {
						Text(ButtonLabels.home)
					}
					.disabled(!canGoHome)
					
					Button(action: {
						if webView.canGoForward {
							webView.goForward()
						}
					}) {
						Text(ButtonLabels.forward)
					}
					.disabled(!canGoForward)
					
					Spacer()
				}
				.padding(.top, 5)
				.padding(.bottom, 20)
			} else {
				VStack(spacing: 40) {
					Spacer()
					Button(action: {
						if webView.canGoBack {
							webView.goBack()
						}
					}) {
						Text(ButtonLabels.back)
					}
					.disabled(!canGoBack)
					Button(action: {
						goHome()
					}) {
						Text(ButtonLabels.home)
					}
					Button(action: {
						if webView.canGoForward {
							webView.goForward()
						}
					}) {
						Text(ButtonLabels.forward)
					}
					.disabled(!canGoForward)
					Spacer()
				}
				.padding([.leading, .trailing], 15)
			}
		}
		.font(.system(size: 34))
		.padding(5)
	}

	func goHome() {
		if let url = u {
			print("goHome")
			webView.load(URLRequest(url: url))
			showProgressView = false
		}
	}
	
	func addSkipBackupAttributeToItem(at path: String) -> Bool {
		var url = URL(fileURLWithPath: path)
		var resourceValues = URLResourceValues()
		resourceValues.isExcludedFromBackup = true
		do {
			try url.setResourceValues(resourceValues)
			return true
		} catch {
			print("Failed to set resource value for \(url): \(error.localizedDescription)")
			return false
		}
	}

	func getFirstZipFilePath() -> String? {
		let fileManager = FileManager.default
		let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

		guard let documentDirectoryPath = documentDirectory?.path else {
			print("Unable to find iTunes File Sharing folder path")
			return nil
		}

		print("iTunes File Sharing folder path: \(documentDirectoryPath)")
		do {
			let files = try fileManager.contentsOfDirectory(atPath: documentDirectoryPath)
			if let firstZipFile = files.first(where: { $0.hasSuffix(".zip") }) {
				return documentDirectoryPath + "/" + firstZipFile
			} else {
				print("No .zip files found in the iTunes File Sharing folder")
				return nil
			}
		} catch {
			print("Error while enumerating files \(documentDirectoryPath): \(error.localizedDescription)")
			return nil
		}
	}
	
	func startServer() {
		errorMsg = ""
		
		var zipPath: String?
		
		#if targetEnvironment(simulator)
		let simZipPath = Constants.simZipPath
		if FileManager.default.fileExists(atPath: simZipPath) {
			zipPath = simZipPath
		}
		#else
		zipPath = getFirstZipFilePath()
		if (zipPath != nil) {
			_ = addSkipBackupAttributeToItem(at: zipPath!)
		}
		#endif
		
		if zipPath != nil {
			print("Starting server with zip file: \(zipPath!)")
			ZipServer.run(zipPath!)
		}
		else {
			errorMsg = "No .zip archive found\nin the FileSharing Folder.\n\nPlease add a .zip archive and retry."
		}
	}
		
}

#Preview {
	ContentView()
}

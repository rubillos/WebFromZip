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

	class Coordinator: NSObject, WKNavigationDelegate {
		var parent: WebView

		init(_ parent: WebView) {
			self.parent = parent
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

	let u = URL(string:"http://localhost:8080/index.html")
	
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
			startServer()
		}
		.onDisappear {
			UIDevice.current.endGeneratingDeviceOrientationNotifications()
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
						Text("◀︎")
					}
					.disabled(!canGoBack)
					
					Button(action: {
						goHome()
					}) {
						Text("⌂")
					}
					.disabled(!canGoHome)
					
					Button(action: {
						if webView.canGoForward {
							webView.goForward()
						}
					}) {
						Text("▶︎")
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
						Text("◀︎")
					}
					.disabled(!canGoBack)
					Button(action: {
						goHome()
					}) {
						Text("⌂")
					}
					Button(action: {
						if webView.canGoForward {
							webView.goForward()
						}
					}) {
						Text("▶︎")
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
			print("go to home")
			webView.load(URLRequest(url: url))
			showProgressView = false
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
		//		let bundlePath = Bundle.main.bundlePath + "/" + zipName

		var zipPath: String?
		
		#if targetEnvironment(simulator)
		let simZipPath = "/Users/randy/Sites/RickAndRandy.zip"
		if FileManager.default.fileExists(atPath: simZipPath) {
			zipPath = simZipPath
		}
		#else
		zipPath = getFirstZipFilePath()
		#endif
		
		if zipPath != nil {
			print("Starting server with zip file: \(zipPath!)")
			
			NotificationCenter.default.addObserver(forName: .zipServerStarted, object: nil, queue: .main) { _ in
				self.goHome()
			}
			
			Task {
				do {
					try await ZipServer.run(zipPath!)
				} catch {
					print("Failed to start server: \(error)")
					errorMsg = "Failed to start server: \(error)"
				}
			}
			
			self.canGoHome = true
		}
		else {
			errorMsg = "No .zip archive found\nin the FileSharing Folder.\n\nPlease add a .zip archive and retry."
		}
	}
		
}

#Preview {
	ContentView()
}

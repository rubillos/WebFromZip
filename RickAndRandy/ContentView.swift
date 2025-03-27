import SwiftUI
@preconcurrency import WebKit
import Foundation

//NSLog(@"%@", NSHomeDirectory());

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
	@State private var canGoForward = false
	@State private var showProgressView = true
	@State private var orientation = UIDeviceOrientation.portrait

	//	let u = URL(string:"https://rickandrandy.com")
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
				self.orientation = UIDevice.current.orientation
			}
			UIDevice.current.beginGeneratingDeviceOrientationNotifications()
			
			NotificationCenter.default.addObserver(forName: .serverStarted, object: nil, queue: .main) { _ in
				self.goHome()
			}
			
			Task {
				do {
					try await ZipServer.run()
				} catch {
					print("Failed to start server: \(error)")
				}
			}
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
			if showProgressView {
				ProgressView()
					.progressViewStyle(CircularProgressViewStyle())
					.scaleEffect(2)
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
				.padding(.bottom, 15)
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
				.padding([.leading, .trailing], 10)
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
}

#Preview {
	ContentView()
}

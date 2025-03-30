//
//  Constants.swift
//  WebFromZip
//
//  Created by Randy on 3/29/25.
//

import Foundation

struct Constants {
	static let mainWebURL = "rickandrandy.com"
	
	static let simZipPath = "/Users/randy/Sites/RickAndRandy.zip"
	
	static let pathRegexes = [
		["@\\d+x", ""],
		["-360|-540|-2160", "-1080"],
		[".m4v", "-HEVC.m4v"]
	]

	static let localhost = "localhost:8080"
	static let httpScheme = "http://"
	static let httpsScheme = "https://"
	static let mainWebURLwww = "www.\(mainWebURL)"
	static let defaultIndex = "index.html"
	static let slashChar = "/"
	static let homePage = "\(httpScheme)\(localhost)\(slashChar)\(defaultIndex)"
}


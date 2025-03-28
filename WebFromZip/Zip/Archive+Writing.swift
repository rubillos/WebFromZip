//
//  Archive+Writing.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Archive {
	enum ModifyOperation: Int {
		case remove = -1
		case add = 1
	}
	
	typealias EndOfCentralDirectoryStructure = (EndOfCentralDirectoryRecord, ZIP64EndOfCentralDirectory?)
}

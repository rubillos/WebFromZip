//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2021-2021 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Half inspired by Reader class from John Sundell's Ink project
// https://github.com/JohnSundell/Ink/blob/master/Sources/Ink/Internal/Reader.swift
// with optimisation working ie removing String and doing my own UTF8 processing inspired by Fabian Fett's work in
// https://github.com/fabianfett/pure-swift-json/blob/master/Sources/PureSwiftJSONParsing/DocumentReader.swift

extension StringProtocol {

	static func hexToAscii(_ hex: UInt8) -> UInt8 {
		switch hex {
		case 0x0:
			return UInt8(ascii: "0")
		case 0x1:
			return UInt8(ascii: "1")
		case 0x2:
			return UInt8(ascii: "2")
		case 0x3:
			return UInt8(ascii: "3")
		case 0x4:
			return UInt8(ascii: "4")
		case 0x5:
			return UInt8(ascii: "5")
		case 0x6:
			return UInt8(ascii: "6")
		case 0x7:
			return UInt8(ascii: "7")
		case 0x8:
			return UInt8(ascii: "8")
		case 0x9:
			return UInt8(ascii: "9")
		case 0xA:
			return UInt8(ascii: "A")
		case 0xB:
			return UInt8(ascii: "B")
		case 0xC:
			return UInt8(ascii: "C")
		case 0xD:
			return UInt8(ascii: "D")
		case 0xE:
			return UInt8(ascii: "E")
		case 0xF:
			return UInt8(ascii: "F")
		default:
			fatalError("Invalid hex digit: \(hex)")
		}
	}

	static func asciiToHex(_ ascii: UInt8) -> UInt8? {
		switch ascii {
		case UInt8(ascii: "0"):
			return 0x0
		case UInt8(ascii: "1"):
			return 0x1
		case UInt8(ascii: "2"):
			return 0x2
		case UInt8(ascii: "3"):
			return 0x3
		case UInt8(ascii: "4"):
			return 0x4
		case UInt8(ascii: "5"):
			return 0x5
		case UInt8(ascii: "6"):
			return 0x6
		case UInt8(ascii: "7"):
			return 0x7
		case UInt8(ascii: "8"):
			return 0x8
		case UInt8(ascii: "9"):
			return 0x9
		case UInt8(ascii: "A"), UInt8(ascii: "a"):
			return 0xA
		case UInt8(ascii: "B"), UInt8(ascii: "b"):
			return 0xB
		case UInt8(ascii: "C"), UInt8(ascii: "c"):
			return 0xC
		case UInt8(ascii: "D"), UInt8(ascii: "d"):
			return 0xD
		case UInt8(ascii: "E"), UInt8(ascii: "e"):
			return 0xE
		case UInt8(ascii: "F"), UInt8(ascii: "f"):
			return 0xF
		default:
			return nil
		}
	}

	func removingURLPercentEncoding(excluding: Set<UInt8> = []) -> String? {
		let fastResult = utf8.withContiguousStorageIfAvailable {
			Self.removingURLPercentEncoding(utf8Buffer: $0, excluding: excluding)
		}
		if let fastResult {
			return fastResult
		} else {
			return Self.removingURLPercentEncoding(utf8Buffer: utf8, excluding: excluding)
		}
	}

	static func removingURLPercentEncoding(utf8Buffer: some Collection<UInt8>, excluding: Set<UInt8> = []) -> String? {
		let result: String? = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: utf8Buffer.count) { buffer -> String? in
			var i = 0
			var byte: UInt8 = 0
			var hexDigitsRequired = 0
			for v in utf8Buffer {
				if v == UInt8(ascii: "%") {
					guard hexDigitsRequired == 0 else {
						return nil
					}
					hexDigitsRequired = 2
				} else if hexDigitsRequired > 0 {
					guard let hex = asciiToHex(v) else {
						return nil
					}
					if hexDigitsRequired == 2 {
						byte = hex << 4
					} else if hexDigitsRequired == 1 {
						byte += hex
						if excluding.contains(byte) {
							// Keep the original percent-encoding for this byte
							i = buffer[i...i + 2].initialize(fromContentsOf: [UInt8(ascii: "%"), hexToAscii(byte >> 4), v])
						} else {
							buffer[i] = byte
							i += 1
							byte = 0
						}
					}
					hexDigitsRequired -= 1
				} else {
					buffer[i] = v
					i += 1
				}
			}
			guard hexDigitsRequired == 0 else {
				return nil
			}
			return String(decoding: buffer[..<i], as: UTF8.self)
		}
		return result
	}
}

/// Reader object for parsing String buffers
struct ZipParser: Sendable {
    enum Error: Swift.Error {
        case overflow
        case unexpected
        case emptyString
        case invalidUTF8
    }

    /// Create a ZipParser object
    /// - Parameter string: UTF8 data to parse
    init?(_ utf8Data: some Collection<UInt8>, validateUTF8: Bool = true) {
        if let buffer = utf8Data as? [UInt8] {
            self.buffer = buffer
        } else {
            self.buffer = Array(utf8Data)
        }
        self.index = 0
        self.range = 0..<self.buffer.endIndex

        // should check that the data is valid utf8
        if validateUTF8 == true, self.validateUTF8() == false {
            return nil
        }
    }

    init(_ string: String) {
        self.buffer = Array(string.utf8)
        self.index = 0
        self.range = 0..<self.buffer.endIndex
    }

    /// Return contents of ZipParser as a string
    var count: Int {
        self.range.count
    }

    /// Return contents of ZipParser as a string
    var string: String {
        makeString(self.buffer[self.range])
    }

    private var buffer: [UInt8]
    private var index: Int
    private let range: Range<Int>
}

// MARK: sub-parsers

extension ZipParser {
    /// initialise a parser that parses a section of the buffer attached to another parser
    private init(_ parser: ZipParser, range: Range<Int>) {
        self.buffer = parser.buffer
        self.index = range.startIndex
        self.range = range

        precondition(range.startIndex >= 0 && range.endIndex <= self.buffer.endIndex)
        // check we arent in the middle of a UTF8 character
        precondition(range.startIndex == self.buffer.endIndex || self.buffer[range.startIndex] & 0xC0 != 0x80)
    }

    /// initialise a parser that parses a section of the buffer attached to this parser
    func subParser(_ range: Range<Int>) -> ZipParser {
		ZipParser(self, range: range)
    }
}

extension ZipParser {
    /// Return current character
    /// - Throws: .overflow
    /// - Returns: Current character
    mutating func character() throws -> Unicode.Scalar {
        guard !self.reachedEnd() else { throw Error.overflow }
        return unsafeCurrentAndAdvance()
    }

    /// Read the current character and return if it is as intended. If character test returns true then move forward 1
    /// - Parameter char: character to compare against
    /// - Throws: .overflow
    /// - Returns: If current character was the one we expected
    mutating func read(_ char: Unicode.Scalar) throws -> Bool {
        let initialIndex = self.index
        let c = try character()
        guard c == char else {
            self.index = initialIndex
            return false
        }
        return true
    }

    /// Read the current character and check if it is in a set of characters If character test returns true then move forward 1
    /// - Parameter characterSet: Set of characters to compare against
    /// - Throws: .overflow
    /// - Returns: If current character is in character set
    mutating func read(_ characterSet: Set<Unicode.Scalar>) throws -> Bool {
        let initialIndex = self.index
        let c = try character()
        guard characterSet.contains(c) else {
            self.index = initialIndex
            return false
        }
        return true
    }

    /// Compare characters at current position against provided string. If the characters are the same as string provided advance past string
    /// - Parameter string: String to compare against
    /// - Throws: .overflow, .emptyString
    /// - Returns: If characters at current position equal string
    mutating func read(_ string: String) throws -> Bool {
        let initialIndex = self.index
        guard string.count > 0 else { throw Error.emptyString }
        let subString = try read(count: string.count)
        guard subString.string == string else {
            self.index = initialIndex
            return false
        }
        return true
    }

    /// Read next so many characters from buffer
    /// - Parameter count: Number of characters to read
    /// - Throws: .overflow
    /// - Returns: The string read from the buffer
    mutating func read(count: Int) throws -> ZipParser {
        var count = count
        var readEndIndex = self.index
        while count > 0 {
            guard readEndIndex != self.range.endIndex else { throw Error.overflow }
            readEndIndex = skipUTF8Character(at: readEndIndex)
            count -= 1
        }
        let result = self.subParser(self.index..<readEndIndex)
        self.index = readEndIndex
        return result
    }

    /// Read from buffer until we hit a character. Position after this is of the character we were checking for
    /// - Parameter until: Unicode.Scalar to read until
    /// - Throws: .overflow if we hit the end of the buffer before reading character
    /// - Returns: String read from buffer
    @discardableResult mutating func read(until: Unicode.Scalar, throwOnOverflow: Bool = true) throws -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd() {
            if unsafeCurrent() == until {
                return self.subParser(startIndex..<self.index)
            }
            unsafeAdvance()
        }
        if throwOnOverflow {
            _setPosition(startIndex)
            throw Error.overflow
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Read from buffer until we hit a character in supplied set. Position after this is of the character we were checking for
    /// - Parameter characterSet: Unicode.Scalar set to check against
    /// - Throws: .overflow
    /// - Returns: String read from buffer
    @discardableResult mutating func read(until characterSet: Set<Unicode.Scalar>, throwOnOverflow: Bool = true) throws -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd() {
            if characterSet.contains(unsafeCurrent()) {
                return self.subParser(startIndex..<self.index)
            }
            unsafeAdvance()
        }
        if throwOnOverflow {
            _setPosition(startIndex)
            throw Error.overflow
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Read from buffer until we hit a character that returns true for supplied closure. Position after this is of the character we were checking for
    /// - Parameter until: Function to test
    /// - Throws: .overflow
    /// - Returns: String read from buffer
    @discardableResult mutating func read(until: (Unicode.Scalar) -> Bool, throwOnOverflow: Bool = true) throws -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd() {
            if until(unsafeCurrent()) {
                return self.subParser(startIndex..<self.index)
            }
            unsafeAdvance()
        }
        if throwOnOverflow {
            _setPosition(startIndex)
            throw Error.overflow
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Read from buffer until we hit a character where supplied KeyPath is true. Position after this is of the character we were checking for
    /// - Parameter characterSet: Unicode.Scalar set to check against
    /// - Throws: .overflow
    /// - Returns: String read from buffer
    @discardableResult mutating func read(until keyPath: KeyPath<Unicode.Scalar, Bool>, throwOnOverflow: Bool = true) throws -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd() {
            if unsafeCurrent()[keyPath: keyPath] {
                return self.subParser(startIndex..<self.index)
            }
            unsafeAdvance()
        }
        if throwOnOverflow {
            _setPosition(startIndex)
            throw Error.overflow
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Read from buffer until we hit a string. By default the position after this is of the beginning of the string we were checking for
    /// - Parameter untilString: String to check for
    /// - Parameter throwOnOverflow: Throw errors if we hit the end of the buffer
    /// - Parameter skipToEnd: Should we set the position to after the found string
    /// - Throws: .overflow, .emptyString
    /// - Returns: String read from buffer
    @discardableResult mutating func read(untilString: String, throwOnOverflow: Bool = true, skipToEnd: Bool = false) throws -> ZipParser {
        var untilString = untilString
        return try untilString.withUTF8 { utf8 in
            guard utf8.count > 0 else { throw Error.emptyString }
            let startIndex = self.index
            var foundIndex = self.index
            var untilIndex = 0
            while !self.reachedEnd() {
                if self.buffer[self.index] == utf8[untilIndex] {
                    if untilIndex == 0 {
                        foundIndex = self.index
                    }
                    untilIndex += 1
                    if untilIndex == utf8.endIndex {
                        unsafeAdvance()
                        if skipToEnd == false {
                            self.index = foundIndex
                        }
                        let result = self.subParser(startIndex..<foundIndex)
                        return result
                    }
                } else {
                    untilIndex = 0
                }
                self.index += 1
            }
            if throwOnOverflow {
                _setPosition(startIndex)
                throw Error.overflow
            }
            return self.subParser(startIndex..<self.index)
        }
    }

    /// Read from buffer from current position until the end of the buffer
    /// - Returns: String read from buffer
    @discardableResult mutating func readUntilTheEnd() -> ZipParser {
        let startIndex = self.index
        self.index = self.range.endIndex
        return self.subParser(startIndex..<self.index)
    }

    /// Read while character at current position is the one supplied
    /// - Parameter while: Unicode.Scalar to check against
    /// - Returns: String read from buffer
    @discardableResult mutating func read(while: Unicode.Scalar) -> Int {
        var count = 0
        while !self.reachedEnd(),
            unsafeCurrent() == `while`
        {
            unsafeAdvance()
            count += 1
        }
        return count
    }

    /// Read while character at current position is in supplied set
    /// - Parameter while: character set to check
    /// - Returns: String read from buffer
    @discardableResult mutating func read(while characterSet: Set<Unicode.Scalar>) -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd(),
            characterSet.contains(unsafeCurrent())
        {
            unsafeAdvance()
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Read while character returns true for supplied closure
    /// - Parameter while: character set to check
    /// - Returns: String read from buffer
    @discardableResult mutating func read(while: (Unicode.Scalar) -> Bool) -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd(),
            `while`(unsafeCurrent())
        {
            unsafeAdvance()
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Read while character returns true for supplied KeyPath
    /// - Parameter while: character set to check
    /// - Returns: String read from buffer
    @discardableResult mutating func read(while keyPath: KeyPath<Unicode.Scalar, Bool>) -> ZipParser {
        let startIndex = self.index
        while !self.reachedEnd(),
            unsafeCurrent()[keyPath: keyPath]
        {
            unsafeAdvance()
        }
        return self.subParser(startIndex..<self.index)
    }

    /// Split parser into sections separated by character
    /// - Parameter separator: Separator character
    /// - Returns: arrays of sub parsers
    mutating func split(separator: Unicode.Scalar) -> [ZipParser] {
        var subParsers: [ZipParser] = []
        while !self.reachedEnd() {
            do {
                let section = try read(until: separator)
                subParsers.append(section)
                unsafeAdvance()
            } catch {
                if !self.reachedEnd() {
                    subParsers.append(self.readUntilTheEnd())
                }
            }
        }
        return subParsers
    }

    /// Return whether we have reached the end of the buffer
    /// - Returns: Have we reached the end
    func reachedEnd() -> Bool {
        self.index == self.range.endIndex
    }
}

/// Public versions of internal functions which include tests for overflow
extension ZipParser {
    /// Return the character at the current position
    /// - Throws: .overflow
    /// - Returns: Unicode.Scalar
    func current() -> Unicode.Scalar {
        guard !self.reachedEnd() else { return Unicode.Scalar(0) }
        return unsafeCurrent()
    }

    /// Move forward one character
    /// - Throws: .overflow
    mutating func advance() throws {
        guard !self.reachedEnd() else { throw Error.overflow }
        return self.unsafeAdvance()
    }

    /// Move forward so many character
    /// - Parameter amount: number of characters to move forward
    /// - Throws: .overflow
    mutating func advance(by amount: Int) throws {
        var amount = amount
        while amount > 0 {
            guard !self.reachedEnd() else { throw Error.overflow }
            self.index = skipUTF8Character(at: self.index)
            amount -= 1
        }
    }

    /// Move backwards one character
    /// - Throws: .overflow
    mutating func retreat() throws {
        guard self.index > self.range.startIndex else { throw Error.overflow }
        self.index = backOneUTF8Character(at: self.index)
    }

    /// Move back so many characters
    /// - Parameter amount: number of characters to move back
    /// - Throws: .overflow
    mutating func retreat(by amount: Int) throws {
        var amount = amount
        while amount > 0 {
            guard self.index > self.range.startIndex else { throw Error.overflow }
            self.index = backOneUTF8Character(at: self.index)
            amount -= 1
        }
    }

    /// Move parser to beginning of string
    mutating func moveToStart() {
        self.index = self.range.startIndex
    }

    /// Move parser to end of string
    mutating func moveToEnd() {
        self.index = self.range.endIndex
    }

    mutating func unsafeAdvance() {
        self.index = skipUTF8Character(at: self.index)
    }

    mutating func unsafeAdvance(by amount: Int) {
        var amount = amount
        while amount > 0 {
            self.index = skipUTF8Character(at: self.index)
            amount -= 1
        }
    }
}

/// extend Parser to conform to Sequence
extension ZipParser: Sequence {
    public typealias Element = Unicode.Scalar

    public func makeIterator() -> Iterator {
        Iterator(self)
    }

    public struct Iterator: IteratorProtocol {
        public typealias Element = Unicode.Scalar

        var parser: ZipParser

        init(_ parser: ZipParser) {
            self.parser = parser
        }

        public mutating func next() -> Unicode.Scalar? {
            guard !self.parser.reachedEnd() else { return nil }
            return self.parser.unsafeCurrentAndAdvance()
        }
    }
}

// internal versions without checks
extension ZipParser {
    fileprivate func unsafeCurrent() -> Unicode.Scalar {
        decodeUTF8Character(at: self.index).0
    }

    fileprivate mutating func unsafeCurrentAndAdvance() -> Unicode.Scalar {
        let (unicodeScalar, index) = decodeUTF8Character(at: self.index)
        self.index = index
        return unicodeScalar
    }

    fileprivate mutating func _setPosition(_ index: Int) {
        self.index = index
    }

    fileprivate func makeString<Bytes: Collection>(_ bytes: Bytes) -> String where Bytes.Element == UInt8, Bytes.Index == Int {
        if let string = bytes.withContiguousStorageIfAvailable({ String(decoding: $0, as: Unicode.UTF8.self) }) {
            return string
        } else {
            return String(decoding: bytes, as: Unicode.UTF8.self)
        }
    }
}

// UTF8 parsing
extension ZipParser {
    func decodeUTF8Character(at index: Int) -> (Unicode.Scalar, Int) {
        var index = index
        let byte1 = UInt32(buffer[index])
        var value: UInt32
        if byte1 & 0xC0 == 0xC0 {
            index += 1
            let byte2 = UInt32(buffer[index] & 0x3F)
            if byte1 & 0xE0 == 0xE0 {
                index += 1
                let byte3 = UInt32(buffer[index] & 0x3F)
                if byte1 & 0xF0 == 0xF0 {
                    index += 1
                    let byte4 = UInt32(buffer[index] & 0x3F)
                    value = (byte1 & 0x7) << 18 + byte2 << 12 + byte3 << 6 + byte4
                } else {
                    value = (byte1 & 0xF) << 12 + byte2 << 6 + byte3
                }
            } else {
                value = (byte1 & 0x1F) << 6 + byte2
            }
        } else {
            value = byte1 & 0x7F
        }
        let unicodeScalar = Unicode.Scalar(value)!
        return (unicodeScalar, index + 1)
    }

    func skipUTF8Character(at index: Int) -> Int {
        if self.buffer[index] & 0x80 != 0x80 { return index + 1 }
        if self.buffer[index + 1] & 0xC0 == 0x80 { return index + 2 }
        if self.buffer[index + 2] & 0xC0 == 0x80 { return index + 3 }
        return index + 4
    }

    func backOneUTF8Character(at index: Int) -> Int {
        if self.buffer[index - 1] & 0xC0 != 0x80 { return index - 1 }
        if self.buffer[index - 2] & 0xC0 != 0x80 { return index - 2 }
        if self.buffer[index - 3] & 0xC0 != 0x80 { return index - 3 }
        return index - 4
    }

    /// same as `decodeUTF8Character` but adds extra validation, so we can make assumptions later on in decode and skip
    func validateUTF8Character(at index: Int) -> (Unicode.Scalar?, Int) {
        var index = index
        let byte1 = UInt32(buffer[index])
        var value: UInt32
        if byte1 & 0xC0 == 0xC0 {
            index += 1
            let byte = UInt32(buffer[index])
            guard byte & 0xC0 == 0x80 else { return (nil, index) }
            let byte2 = UInt32(byte & 0x3F)
            if byte1 & 0xE0 == 0xE0 {
                index += 1
                let byte = UInt32(buffer[index])
                guard byte & 0xC0 == 0x80 else { return (nil, index) }
                let byte3 = UInt32(byte & 0x3F)
                if byte1 & 0xF0 == 0xF0 {
                    index += 1
                    let byte = UInt32(buffer[index])
                    guard byte & 0xC0 == 0x80 else { return (nil, index) }
                    let byte4 = UInt32(byte & 0x3F)
                    value = (byte1 & 0x7) << 18 + byte2 << 12 + byte3 << 6 + byte4
                } else {
                    value = (byte1 & 0xF) << 12 + byte2 << 6 + byte3
                }
            } else {
                value = (byte1 & 0x1F) << 6 + byte2
            }
        } else {
            value = byte1 & 0x7F
        }
        let unicodeScalar = Unicode.Scalar(value)
        return (unicodeScalar, index + 1)
    }

    /// return if the buffer is valid UTF8
    func validateUTF8() -> Bool {
        var index = self.range.startIndex
        while index < self.range.endIndex {
            let (scalar, newIndex) = self.validateUTF8Character(at: index)
            guard scalar != nil else { return false }
            index = newIndex
        }
        return true
    }

    private static let asciiHexValues: [UInt8] = [
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x00
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x08
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x10
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x18
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x20
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x28
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,  // 0x30
        0x08, 0x09, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x38
        0x80, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x80,  // 0x40
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x48
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x50
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x58
        0x80, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x80,  // 0x60
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x68
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x70
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x78

        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x80
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x88
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x90
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0x98
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xA0
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xA8
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xB0
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xB8
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xC0
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xC8
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xD0
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xD8
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xE0
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xE8
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xF0
        0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,  // 0xF8
    ]

    /// percent decode UTF8
    public func percentDecode() -> String? {
        String.removingURLPercentEncoding(utf8Buffer: self.buffer[self.index..<self.range.endIndex])
    }
}

extension Unicode.Scalar {
    var isWhitespace: Bool {
        properties.isWhitespace
    }

    var isNewline: Bool {
        switch self.value {
        case 0x000A...0x000D: return true  // LF ... CR
        case 0x0085: return true  // NEXT LINE (NEL)
        case 0x2028: return true  // LINE SEPARATOR
        case 0x2029: return true  // PARAGRAPH SEPARATOR
        default: return false
        }
    }
}

extension Set<Unicode.Scalar> {
    init(_ string: String) {
        self = Set(string.unicodeScalars)
    }
}

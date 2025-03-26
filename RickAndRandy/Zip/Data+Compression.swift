//
//  Data+Compression.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

#if canImport(zlib)
import zlib
#endif

/// The compression method of an `Entry` in a ZIP `Archive`.
public enum CompressionMethod: UInt16 {
    /// Indicates that an `Entry` has no compression applied to its contents.
    case none = 0
    /// Indicates that contents of an `Entry` have been compressed with a zlib compatible Deflate algorithm.
    case deflate = 8
}

/// An unsigned 32-Bit Integer representing a checksum.
public typealias CRC32 = UInt32
/// A custom handler that consumes a `Data` object containing partial entry data.
/// - Parameters:
///   - data: A chunk of `Data` to consume.
/// - Throws: Can throw to indicate errors during data consumption.
public typealias Consumer = (_ data: Data) throws -> Void
/// A custom handler that receives a position and a size that can be used to provide data from an arbitrary source.
/// - Parameters:
///   - position: The current read position.
///   - size: The size of the chunk to provide.
/// - Returns: A chunk of `Data`.
/// - Throws: Can throw to indicate errors in the data source.
public typealias Provider = (_ position: Int64, _ size: Int) throws -> Data

extension Data {
    enum CompressionError: Error {
        case invalidStream
        case corruptedData
    }

    /// Calculate the `CRC32` checksum of the receiver.
    ///
    /// - Parameter checksum: The starting seed.
    /// - Returns: The checksum calculated from the bytes of the receiver and the starting seed.
    public func crc32(checksum: CRC32) -> CRC32 {
        #if canImport(zlib)
        return withUnsafeBytes { bufferPointer in
            let length = UInt32(count)
            return CRC32(zlib.crc32(UInt(checksum), bufferPointer.bindMemory(to: UInt8.self).baseAddress, length))
        }
        #else
        return self.builtInCRC32(checksum: checksum)
        #endif
    }

}


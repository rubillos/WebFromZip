//
//  Archive+BackingConfiguration.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Archive {

    struct BackingConfiguration {
        let file: FILEPointer
        let endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord
        let zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?

        init(file: FILEPointer,
             endOfCentralDirectoryRecord: EndOfCentralDirectoryRecord,
             zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?) {
            self.file = file
            self.endOfCentralDirectoryRecord = endOfCentralDirectoryRecord
            self.zip64EndOfCentralDirectory = zip64EndOfCentralDirectory
        }
    }

    static func makeBackingConfiguration(for url: URL, mode: AccessMode) throws
    -> BackingConfiguration {
        let fileManager = FileManager()
        switch mode {
        case .read:
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            guard let archiveFile = fopen(fileSystemRepresentation, "rb") else {
                throw POSIXError(errno, path: url.path)
            }
            guard let (eocdRecord, zip64EOCD) = Archive.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                throw ArchiveError.missingEndOfCentralDirectoryRecord
            }
            return BackingConfiguration(file: archiveFile,
                                        endOfCentralDirectoryRecord: eocdRecord,
                                        zip64EndOfCentralDirectory: zip64EOCD)
        case .create:
            let endOfCentralDirectoryRecord = EndOfCentralDirectoryRecord(numberOfDisk: 0, numberOfDiskStart: 0,
                                                                          totalNumberOfEntriesOnDisk: 0,
                                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                                          sizeOfCentralDirectory: 0,
                                                                          offsetToStartOfCentralDirectory: 0,
                                                                          zipFileCommentLength: 0,
                                                                          zipFileCommentData: Data())
            try endOfCentralDirectoryRecord.data.write(to: url, options: .withoutOverwriting)
            fallthrough
        case .update:
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            guard let archiveFile = fopen(fileSystemRepresentation, "rb+") else {
                throw POSIXError(errno, path: url.path)
            }
            guard let (eocdRecord, zip64EOCD) = Archive.scanForEndOfCentralDirectoryRecord(in: archiveFile) else {
                throw ArchiveError.missingEndOfCentralDirectoryRecord
            }
            fseeko(archiveFile, 0, SEEK_SET)
            return BackingConfiguration(file: archiveFile,
                                        endOfCentralDirectoryRecord: eocdRecord,
                                        zip64EndOfCentralDirectory: zip64EOCD)
        }
    }

}

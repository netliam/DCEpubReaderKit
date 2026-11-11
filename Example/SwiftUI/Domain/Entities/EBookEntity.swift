//
//  EBookEntity.swift
//  DCEpubReaderKit
//
//  Created by Josep Cerdá Penadés on 5/2/26.
//

import Foundation

struct EBookEntity {
    let uuid: String
    let title: String
    let author: String
    let coverPath: String
    let language: String
    let publisher: String
    let bookVersion: String
    let bookDate: String
    let descriptionHTML: String
    let createdAt: Int64
    let updatedAt: Int64

    var basePath: URL? {
        FileHelper.shared.bookDirectory(for: uuid)
    }
}

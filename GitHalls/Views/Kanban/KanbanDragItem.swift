//
//  KanbanDragItem.swift
//  GitHalls
//

import CoreTransferable
import UniformTypeIdentifiers

/// What a drag on the board carries. One type for cards and columns so a column
/// can tell, on drop, which of the two it was handed.
enum KanbanDragItem: Codable, Transferable, Equatable {
    case card(key: String)
    case column(status: String)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

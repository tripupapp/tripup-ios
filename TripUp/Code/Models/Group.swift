//
//  Group.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 13/03/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation

struct Group: Hashable {
    let uuid: UUID
    let name: String
    let fingerprint: String
    let members: Set<User>
    let album: Album
}

extension Group: Comparable {
    static func < (lhs: Group, rhs: Group) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        } else if lhs.album.startDate != rhs.album.startDate {
            return lhs.album.startDate < rhs.album.startDate
        } else {
            return lhs.uuid.string < rhs.uuid.string
        }
    }
}

extension Group {
    enum Comparison {
        case startDate(ascending: Bool)
    }
}

extension Sequence where Iterator.Element == Group {
    func sorted(by comparator: Group.Comparison) -> [Group] {
        switch comparator {
        case .startDate(let ascending):
            let dateComparator: (Date, Date) -> Bool = ascending ? (<) : (>)
            return self.sorted { (group1, group2) -> Bool in
                if group1.album.startDate != group2.album.startDate {
                    return dateComparator(group1.album.startDate, group2.album.startDate)
                } else {
                    return group1 < group2    // fallback to ascending sort whenever there's a conflict with the start date
                }
            }
        }
    }
}

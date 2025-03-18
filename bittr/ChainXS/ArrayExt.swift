//
//  ArrayExt.swift
//  ChainXS
//
//  Created by raidshift
//

import Foundation

public extension [String] {
    func binarySearch(key: String) -> Int? {
        var lowerBound = 0
        var upperBound = count
        while lowerBound < upperBound {
            let midIndex = lowerBound + (upperBound - lowerBound) / 2
            if self[midIndex] == key {
                return midIndex
            } else if self[midIndex] < key {
                lowerBound = midIndex + 1
            } else {
                upperBound = midIndex
            }
        }
        return nil
    }
}

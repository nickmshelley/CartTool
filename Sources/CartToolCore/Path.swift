//
//  Path.swift
//
//  Created by Bart Whiteley on 11/8/17.
//  Copyright (c) 2018 Ancestry.com. All rights reserved.
//

import Foundation

struct Path: ExpressibleByStringLiteral {
    typealias StringLiteralType = String
    
    init(stringLiteral rawValue: String) {
        self.init(rawValue)
    }
    
    init(_ string: String) {
        var path: String
        if string.hasPrefix("/") {
            path = string
        } else {
            path = FileManager.default.currentDirectoryPath + "/" + string
        }
        self.absolute = Path.removeDotDotsAndTrim(path)
    }
    
    let absolute: String
    
    var baseName: String {
        return absolute.components(separatedBy: "/").last ?? ""
    }
    
    var parent: Path {
        var components: [String] = absolute.components(separatedBy: "/")
        _ = components.popLast()
        let parentStr = "/" + components.joined(separator: "/")
        return Path(parentStr)
    }
    
    func pathByAppending(component: String) -> Path {
        let trimmed = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Path(absolute + "/" + trimmed)
    }
    
    private static func removeDotDotsAndTrim(_ path: String) -> String {
        let trimmed: String = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = trimmed.components(separatedBy: "/")
        var newComponents: [String] = []
        for component in components {
            if component == ".." {
                _ = newComponents.popLast()
                continue
            }
            newComponents.append(component)
        }
        return "/" + newComponents.joined(separator: "/")
    }
}


// PkgLiftCocoaPods/PodspecJSONPointer.swift

import Foundation

enum PodspecJSONPointer {
    static func appending(_ component: String, to path: String) -> String {
        let escaped = component
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
        return "\(path)/\(escaped)"
    }
}

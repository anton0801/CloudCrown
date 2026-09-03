import Foundation
import UIKit

struct DeviceFacts {
    let osLine: String
    let vessel: String
    let localeTag: String
    let buildTag: String
    let hull: String
    let timeZone: String

    static func current() -> DeviceFacts {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return DeviceFacts(
            osLine: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            vessel: AppConstants.bundleIdentifier,
            localeTag: Locale.preferredLanguages.first ?? Locale.current.identifier,
            buildTag: "\(version) (\(build))",
            hull: machineIdentifier(),
            timeZone: TimeZone.current.identifier
        )
    }

    private static func machineIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let identifier = mirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

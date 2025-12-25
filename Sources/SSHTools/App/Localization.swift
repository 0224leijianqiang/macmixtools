import Foundation

// Standard localization extension utilizing the package module bundle.
// This allows the app to respect the system language settings automatically.
extension String {
    var localized: String {
        return NSLocalizedString(self, bundle: .module, comment: "")
    }
}

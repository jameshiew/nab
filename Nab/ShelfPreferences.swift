import Foundation

enum ShelfPreferences {
    private static let topLeftXKey = "shelfTopLeftX"
    private static let topLeftYKey = "shelfTopLeftY"

    static var topLeft: CGPoint? {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: topLeftXKey) != nil,
                defaults.object(forKey: topLeftYKey) != nil
            else { return nil }
            return CGPoint(
                x: defaults.double(forKey: topLeftXKey),
                y: defaults.double(forKey: topLeftYKey)
            )
        }
        set {
            let defaults = UserDefaults.standard
            if let point = newValue {
                defaults.set(point.x, forKey: topLeftXKey)
                defaults.set(point.y, forKey: topLeftYKey)
            } else {
                defaults.removeObject(forKey: topLeftXKey)
                defaults.removeObject(forKey: topLeftYKey)
            }
        }
    }
}

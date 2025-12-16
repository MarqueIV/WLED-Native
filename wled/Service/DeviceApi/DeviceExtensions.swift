
import Foundation

extension Device {
    var displayName: String {
        if let name = customName, !name.isEmpty {
            return name
        }
        if let name = originalName, !name.isEmpty {
            return name
        }
        return String(localized: "(New Device)")
    }
    
    func getColor(state: WledState?) -> Int64 {
        if let state {
            let colorInfo = state.segment?[0].colors?[0]
            let red = Int64(Double(colorInfo![0]) + 0.5)
            let green = Int64(Double(colorInfo![1]) + 0.5)
            let blue = Int64(Double(colorInfo![2]) + 0.5)
            return (red << 16) | (green << 8) | blue
        }
        // TODO: #statelessDevice verify if 0 is a good default color
        return 0
    }
}

extension Device: Observable { }

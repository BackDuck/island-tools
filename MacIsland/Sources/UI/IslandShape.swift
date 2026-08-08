import SwiftUI

/// Форма острова: сверху почти квадрат, снизу — скругление.
enum IslandShape {
    static var panel: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: IslandTheme.topCornerRadius,
            bottomLeadingRadius: IslandTheme.cornerRadius,
            bottomTrailingRadius: IslandTheme.cornerRadius,
            topTrailingRadius: IslandTheme.topCornerRadius,
            style: .continuous
        )
    }

    static var sidebar: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: IslandTheme.topCornerRadius,
            bottomLeadingRadius: IslandTheme.cornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }
}

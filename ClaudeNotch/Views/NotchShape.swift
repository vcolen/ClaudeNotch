import SwiftUI

/// Shape that mimics the physical MacBook notch: flat top, rounded bottom corners
/// using native squircle (continuous) corners.
struct NotchShape: Shape {
    var bottomRadius: CGFloat = 16

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: rect)
    }
}

#Preview {
    NotchShape()
        .fill(Color.black)
        .frame(width: 220, height: 80)
        .padding(40)
        .background(Color.gray.opacity(0.2))
}

import SwiftUI
import UIKit

struct VXRoot: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("VEEX")
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(.white)
                Text("EXTERNAL")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(7)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.top, 70)
        }
    }
}

final class VXHost: UIHostingController<VXRoot> {
    init() { super.init(rootView: VXRoot()) }
    required init?(coder: NSCoder) { fatalError() }
}

@_cdecl("VXMakePanel")
public func VXMakePanel() -> UIViewController {
    let h = VXHost()
    h.view.backgroundColor = .black
    return h
}

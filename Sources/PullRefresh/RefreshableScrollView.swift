import SwiftUI

public typealias ActionComplete = () -> Void
public typealias RefreshAction = (@escaping ActionComplete) -> Void

public enum RefreshState: Hashable {
    case idle, loading, pulling
}

public struct StateItem: Hashable {
    var state: RefreshState
    var progress: CGFloat

    var isloading: Bool { state == .loading }
    var ispulling: Bool { state == .pulling }
    var idle: Bool { state == .idle }

    mutating func updateProgress(_ progress: CGFloat) {
        self.progress = progress
    }

    mutating func updateState(_ state: RefreshState) {
        self.state = state
    }
}

public struct RefreshableScrollView<
    Content: View,
    PullAnimationView: View,
    SwipupAnimationView: View
>: View {
    ///  Create Refreshable view
    /// - Parameters:
    ///   - pullthreshold: threshold to pull, it is the height of the loading view
    ///   - pullProgress: use pullthreshold and pulloffset to caculate the progress
    ///   - onRefresh: pull refresh action
    ///   - pullAnimationView: refresh animation view
    ///   - enableSwipup: if set to false, load more action will not be triggerd
    ///   - swipupThreshold: same as pullthreshold
    ///   - swipupProgress: default to .constant(0)
    ///   - swipupAnimationView: load more animation view
    ///   - onloadMore: load more action
    ///   - content: content of list view
    public init(
        pullthreshold: CGFloat,
        pullProgress: Binding<StateItem>,
        onRefresh: @escaping RefreshAction,
        @ViewBuilder pullAnimationView: @escaping () -> PullAnimationView,
        enableSwipup: Bool = false,
        swipupThreshold: CGFloat,
        swipupProgress: Binding<StateItem>,
        @ViewBuilder swipupAnimationView: @escaping () -> SwipupAnimationView,
        onloadMore: @escaping RefreshAction,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.pullthreshold = pullthreshold
        self.swipupEnabled = enableSwipup
        self.swipupThreshold = swipupThreshold
        _pullProgress = pullProgress
        _swipupProgress = swipupProgress

        self.onRefresh = onRefresh
        self.loadMore = onloadMore

        self.content = content
        self.pullAnimationView = pullAnimationView
        self.swipupAnimationView = swipupAnimationView
    }

    private var content: () -> Content
    private var pullAnimationView: () -> PullAnimationView
    private var swipupAnimationView: () -> SwipupAnimationView

    private let pullthreshold: CGFloat
    private let swipupEnabled: Bool
    private let swipupThreshold: CGFloat

    private var onRefresh: (@escaping ActionComplete) -> Void
    private var loadMore: (@escaping ActionComplete) -> Void

    @Binding public var pullProgress: StateItem
    @Binding public var swipupProgress: StateItem

    @State private var scrollOffset: CGFloat = 0
    @State private var contentBounds: CGRect = .zero

    public var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                GeometryIndicator(identifier: .floating)
                    .frame(height: 0)
                VStack(spacing: 0) {
                content()
                    // here we get the content bounds
                    .anchorPreference(
                        key: RefreshKeys.Anchor.self,
                        value: .bounds,
                        transform: { [ContentGeoItem(identifier: .content, bounds: $0)] }
                    )

                        // load-more-animation-view
                    if swipupEnabled {
                        ZStack {
                            Rectangle()
                                .foregroundColor(Color.clear)
                                .frame(height: swipupThreshold)
                            swipupAnimationView()
                        }
                    }
                }
                    // use alignmentGuide to make space when loading
                    .alignmentGuide(.top, computeValue: { _ in
                        pullProgress.isloading ? scrollOffset - pullthreshold : 0
                    })

                // pull-to-refresh-animation-view
                ZStack {
                    Rectangle()
                        .foregroundColor(Color.clear)
                        .frame(height: pullthreshold)
                    pullAnimationView()
                }
                .offset(y: pullProgress.isloading ? -scrollOffset : -pullthreshold)
            }
        }
        .backgroundPreferenceValue(RefreshKeys.Anchor.self) { values in
            GeometryReader { proxy in
                backgroundPreferenceView(for: proxy, values: values)
            }
        }
        .onPreferenceChange(RefreshKeys.Geometry.self) { geos in
            let floatingRect = geos.first(where: \.isFloting)?.rect ?? .zero
            // scrollview bounds
            let fixedRect = geos.first(where: \.isFixTop)?.rect ?? .zero

            scrollOffset = floatingRect.minY - fixedRect.minY

            guard scrollOffset > 0 else {
                // handle load more
                guard swipupEnabled,
                      contentBounds.height > 0 else {
                    return
                }

                // offset out of scrollview's bounds
                let cutOffset = -(contentBounds.height - fixedRect.height)
                swipupProgress.updateProgress(max(0, (cutOffset - scrollOffset) / swipupThreshold))

                if scrollOffset <= cutOffset,
                   swipupProgress.idle {
                    swipupProgress.updateState(.pulling)
                } else if scrollOffset > cutOffset - swipupThreshold,
                          swipupProgress.ispulling {
                    swipupProgress = .init(state: .loading, progress: 1)

                    loadMore {
                        withAnimation {
                            swipupProgress = .init(state: .idle, progress: 0)
                        }
                    }
                }

                return
            }

            // handle pull to refresh
            refresh()
        }
    }

    private func backgroundPreferenceView(
        for proxy: GeometryProxy,
        values: [ContentGeoItem]
    ) -> some View {
        if self.swipupEnabled, let prefrenceValue = values.first(where: \.isContent) {
            // use async to avoid [modify duaring updating] warning
            DispatchQueue.main.async {
                self.contentBounds = proxy[prefrenceValue.bounds]
            }
        }

        return GeometryIndicator(identifier: .fixTop)
    }

    private func refresh() {
        guard !pullProgress.isloading else {
            return
        }
        pullProgress.updateProgress(scrollOffset / pullthreshold)
        if scrollOffset > pullthreshold, pullProgress.idle {
            pullProgress.updateState(.pulling)
            // maybe hatapic engine

        } else if scrollOffset <= pullthreshold, pullProgress.ispulling {
            pullProgress = .init(state: .loading, progress: 1)
            // refresh

            onRefresh {
                withAnimation {
                    pullProgress = .init(state: .idle, progress: 0)
                }
            }
        }
    }
}

private struct GeometryItem: Equatable {
    typealias ID = RefreshKeys.ID

    let rect: CGRect
    let identifier: ID

    var isFloting: Bool { identifier == .floating }
    var isFixTop: Bool { identifier == .fixTop }
}

private struct ContentGeoItem {
    typealias ID = RefreshKeys.ID
    let identifier: ID
    let bounds: Anchor<CGRect>

    var isContent: Bool { identifier == .content }
}

private enum RefreshKeys {
    enum ID: String {
        case floating
        case fixTop
        case content
    }

    struct Geometry: PreferenceKey {
        static var defaultValue: [GeometryItem] = []

        static func reduce(value: inout [GeometryItem], nextValue: () -> [GeometryItem]) {
            value.append(contentsOf: nextValue())
        }
    }

    struct Anchor: PreferenceKey {
      static var defaultValue: [ContentGeoItem] = []

      static func reduce(
        value: inout [ContentGeoItem],
        nextValue: () -> [ContentGeoItem]) {
        value.append(contentsOf: nextValue())
      }
    }
}

private struct GeometryIndicator: View {
    let identifier: GeometryItem.ID
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: RefreshKeys.Geometry.self,
                    value: [
                        GeometryItem(
                            rect: proxy.frame(in: .global),
                            identifier: identifier
                        )
                    ]
                )
        }
    }
}

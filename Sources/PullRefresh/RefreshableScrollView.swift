import SwiftUI

public typealias ActionComplete = () -> Void
public typealias RefreshAction = (@escaping ActionComplete) -> Void

enum ActionState {
    case pulling
    case swiping
    case ignore
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
        pullProgress: Binding<InterActionState>,
        onRefresh: @escaping RefreshAction,
        @ViewBuilder pullAnimationView: @escaping () -> PullAnimationView,
        enableSwipup: Bool = false,
        swipupThreshold: CGFloat,
        swipupProgress: Binding<InterActionState>,
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

    @Binding public var pullProgress: InterActionState
    @Binding public var swipupProgress: InterActionState

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
            // use async to avoid [multiple updating during a single frame] warning
            DispatchQueue.main.async {
                let floatingRect = geos.first(where: \.isFloting)?.rect ?? .zero
                // scrollview bounds
                let containerRect = geos.first(where: \.isFixTop)?.rect ?? .zero

                let scrollOffset = floatingRect.minY - containerRect.minY
                let diff = scrollOffset - self.scrollOffset

                let direction = diff > 0 ? ActionState.pulling : (diff == 0 ? .ignore : .swiping)
                self.scrollOffset = scrollOffset

                pullingState()
                swipingState(containerRect: containerRect, action: direction)
            }
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

    // MARK: Calculate action state

    private func pullingState() {
        guard self.scrollOffset > 0 else {
            guard self.scrollOffset < 0 else {
                return
            }

            if pullProgress.isloading {
                withAnimation {
                    pullProgress.cancel()
                    pullProgress.updateState(.idle)
                }
            }

            return
        }

        // handle pull to refresh
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
                guard !pullProgress.isCanceled else {
                    return
                }
                withAnimation {
                    pullProgress = .init(state: .idle, progress: 0)
                }
            }
        }
    }

    private func swipingState(containerRect: CGRect, action: ActionState) {
        guard swipupEnabled,
              contentBounds.height > 0 else {
            return
        }

        guard scrollOffset != 0 else {
            return
        }

        let cutOffset = -(contentBounds.height - containerRect.height)
        swipupProgress.updateProgress(max(0, (cutOffset - scrollOffset) / swipupThreshold))

        guard swipupProgress.isloading else {
            // offset out of scrollview's bounds
            if scrollOffset < cutOffset - swipupThreshold,
               swipupProgress.idle {
                swipupProgress.updateState(.pulling)
            } else if scrollOffset >= cutOffset - swipupThreshold,
                      swipupProgress.ispulling {
                swipupProgress = .init(state: .loading, progress: 1)
                loadMore {
                    guard !swipupProgress.isCanceled else {
                        return
                    }
                    withAnimation {
                        swipupProgress = .init(state: .idle, progress: 0)
                    }
                }
            }
            return
        }

        if action == .pulling, scrollOffset >= cutOffset - swipupThreshold  {
            withAnimation {
                swipupProgress.cancel()
                swipupProgress.updateState(.idle)
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

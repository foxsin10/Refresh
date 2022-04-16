import SwiftUI

// Note this will be used when enableSwipup set to false
struct Emptyloading: View {
    typealias Body = Never
    var body: Never { fatalError() }
}

struct PullModifer<T: View>: ViewModifier {
    init(
        pullthreshold: CGFloat,
        pullProgress: Binding<InterActionState>,
        onRefresh: @escaping RefreshAction,
        @ViewBuilder pullAnimationView: @escaping () -> T
    ) {
        self.pullthreshold = pullthreshold
        _pullProgress = pullProgress
        self.pullAnimationView = pullAnimationView
        self.onRefresh = onRefresh
    }

    @Binding var pullProgress: InterActionState
    private var pullAnimationView: () -> T
    private let pullthreshold: CGFloat
    private let onRefresh: RefreshAction
    

    func body(content: Content) -> RefreshableScrollView<Content, T, Emptyloading> {
        RefreshableScrollView(
            pullthreshold: pullthreshold,
            pullProgress: $pullProgress,
            onRefresh: onRefresh,
            pullAnimationView: pullAnimationView,
            enableSwipup: false,
            swipupThreshold: 0,
            swipupProgress: .constant(.init(state: .idle, progress: 0)),
            swipupAnimationView: { Emptyloading() },
            onloadMore: { _ in },
            content: { content }
        )
    }
}

public extension View {
    @ViewBuilder func onRefresh<V: View>(
        pullthreshold: CGFloat,
        pullProgress: Binding<InterActionState>,
        onRefresh: @escaping RefreshAction,
        @ViewBuilder pullAnimationView: @escaping () -> V
    ) -> some View {
        modifier(
            PullModifer(
                pullthreshold: pullthreshold,
                pullProgress: pullProgress,
                onRefresh: onRefresh,
                pullAnimationView: { pullAnimationView() }
            )
        )
    }
}

#if compiler(>=5.5)
public extension View {
    @ViewBuilder func onRefresh<V: View>(
        pullthreshold: CGFloat,
        pullProgress: Binding<InterActionState>,
        asyncAction: @escaping @Sendable () async -> Void,
        @ViewBuilder pullAnimationView: @escaping () -> V
    ) -> some View {
        modifier(
            PullModifer(
                pullthreshold: pullthreshold,
                pullProgress: pullProgress,
                onRefresh: { done in
                    Task {
                        await asyncAction()
                        done()
                    }
                },
                pullAnimationView: { pullAnimationView() }
            )
        )
    }
}
#endif

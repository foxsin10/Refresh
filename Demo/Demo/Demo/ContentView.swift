//
//  ContentView.swift
//  PullToRefresh
//
//  Created by yzj on 2022/4/14.
//

import Combine
import SwiftUI
//import PullRefresh

@dynamicMemberLookup
final class PullViewModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var pullProgress: InterActionState = .init(state: .idle, progress: 0) {
        didSet {
            guard oldValue.isloading != pullProgress.isloading else {
                return
            }
            objectWillChange.send()
        }
    }

    var swipeProgress: InterActionState = .init(state: .idle, progress: 0) {
        didSet {
            guard oldValue.isloading != swipeProgress.isloading else {
                return
            }

            withAnimation {
                objectWillChange.send()
            }
        }
    }
    
    subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<PullViewModel, Value>) -> Binding<Value> {
        Binding(
            get: {
                self[keyPath: keyPath]
            },
            set: { value, _ in
                self[keyPath: keyPath] = value
            }
        )
    }
}

struct ContentView: View {
    @State var items: [String] = []

    @StateObject var vm = PullViewModel()

    @State var refreshing: Bool = false

    @State var loading = false
    @State var noMore = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pull to refresh")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Spacer()
            }
            .background(Color.cyan)

            Divider()

            RefreshableScrollView(
                pullthreshold: 50,
                pullProgress: $vm.pullProgress,
                onRefresh: { done in
                    print("pull to refresh")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        defer { done() }
                        guard !vm.pullProgress.isCanceled else {
                            return
                        }
                        print("pull to refresh finish")
                    }
                },
                pullAnimationView: {
                    buildLoadingView(progress: vm.pullProgress.progress)
                },
                enableSwipup: false,
                swipupThreshold: 50,
                swipupProgress: $vm.swipeProgress,
                swipupAnimationView: {
                    buildLoadMoreView(progress: vm.swipeProgress.progress)
                },
                onloadMore: { done in
                    print("swip to load more")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        defer { done() }
                        guard !vm.swipeProgress.isCanceled else {
                            return
                        }
                        print("swip to load more finish")
                    }
                }
            ) {
                contentView
            }

        }
        .background(Color.black.opacity(0.06))
        .onAppear {
            refresh()
        }
    }

    private func buildLoadingView(progress: CGFloat) -> some View {
        return Image(systemName: "arrow.down")
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.black)
            .opacity(min(1, progress))
            .rotationEffect(
                Angle(radians: Double(min(1, max(0, progress))) * .pi)
            )
    }

    private func buildLoadMoreView(progress: CGFloat) -> some View {
        return Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.black)
            .opacity(min(1, progress))
            .rotationEffect(
                Angle(radians: Double(min(1, max(0, progress))) * .pi)
            )
    }

    private var contentView: some View {
        LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(items, id: \.self) { item in
                    HStack {
                        Text(item)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.black)
                    }
                    .padding()
                }
            } header: {
                Text("List")
                    .font(.subheadline)
                    .padding()
                    .background(.white)
            }
        }
        .background(Color.white)
    }

    func refresh() {
        items = (0 ..< 14).map { "Fake item: \($0 + 1)" }
    }

    func loadMore() {
        let count = items.count
        items.append(
            contentsOf: (0 ..< 10).map { "Fake item: \(count + $0)" }
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

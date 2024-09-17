// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI

public struct GridAuthenticator: View {
    @ObservedObject public var viewModel: GridAuthenticatorViewModel

    public init(_ gridAuthModel: GridAuthenticatorViewModel.GridAuthenticatorOption) {
        viewModel = GridAuthenticatorViewModel(gridAuthModel)
    }

    let columns = Array(repeating: GridItem(.fixed(60), spacing: 40), count: 3)

    public var body: some View {
        VStack {
            if viewModel.debug {
                Text("[DEBUG] Current Pattern: \(viewModel.selectedCardsIndices)")
                    .padding()
                if let eh = viewModel.expectedHash {
                    Text("[DEBUG] Expected Hash: \(eh)")
                        .padding()
                }
                if !viewModel.selectedCardsIndices.isEmpty {
                    Text("[DEBUG] Current Hash: \(viewModel.currentHash)")
                        .padding()
                }
            }
            ZStack {
                LazyVGrid(columns: columns) {
                    ForEach(0 ..< 9, id: \.self) { index in
                        GlowyCircle(index: index, viewModel: viewModel)
                            .padding()
                            .tag(index)
                    }
                }
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .onPreferenceChange(CardPreferenceKey.self) { value in
                    viewModel.cardsData = value
                }
                .coordinateSpace(name: "GridSpace")
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let timelineDate = timeline.date.timeIntervalSinceReferenceDate
                        viewModel.particleSystem.update(date: timelineDate)
                        context.blendMode = .plusLighter
                        context.addFilter(.colorMultiply(viewModel.viewColor))

                        for particle in viewModel.particleSystem.particles {
                            let xPos = particle.x * size.width
                            let yPos = particle.y * size.height
                            context.opacity = 1 - (timelineDate - particle.creationDate)
                            context.draw(viewModel.particleSystem.image, at: CGPoint(x: xPos, y: yPos))
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            viewModel.duringDrag(drag: drag)
                        }
                        .onEnded { _ in
                            viewModel.afterDrag()
                        }
                )
                .ignoresSafeArea()
            }
            .frame(maxWidth: /*@START_MENU_TOKEN@*/ .infinity/*@END_MENU_TOKEN@*/, maxHeight: UIScreen.main.bounds.height * 0.4)

            VStack {
                Text(viewModel.validityText)
                    .foregroundStyle(.red)
                    .padding(.bottom)
                if viewModel.mode == .set {
                    if viewModel.confirmationState == .awaitingConfirmation {
                        Text("Please confirm your pattern")
                            .foregroundStyle(viewModel.viewColor)
                            .padding(.bottom)
                    }
                    if viewModel.selectedCardsIndices.count > 0 && viewModel.locked {
                        HStack {
                            Button {
                                viewModel.selectedCardsIndices = []
                                viewModel.locked = false
                                viewModel.confirmationState = .initial
                                viewModel.firstPatternHash = nil
                            } label: {
                                Text("Reset")
                            }
                            .buttonBorderShape(.capsule)
                            .buttonStyle(BorderedProminentButtonStyle())
                            .tint(viewModel.viewColor)

                            if viewModel.requireConfirmation ?? false && viewModel.confirmationState == .initial {
                                Button {
                                    viewModel.confirmPattern()
                                } label: {
                                    Text("Confirm")
                                }
                                .buttonBorderShape(.capsule)
                                .buttonStyle(BorderedProminentButtonStyle())
                                .tint(viewModel.viewColor)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .modifier(Shake(animatableData: CGFloat(viewModel.incorrectCount)))
    }
}

public struct GlowyCircle: View {
    public var index: Int
    @State public var isBeingTouched: Bool = false
    @ObservedObject public var viewModel: GridAuthenticatorViewModel

    public var body: some View {
        ZStack {
            Circle()
                .foregroundStyle(viewModel.viewColor.opacity(0.9))
                .frame(width: 60, height: 60)
            Circle()
                .foregroundStyle(viewModel.viewColor.opacity(isBeingTouched ? 0.6 : 0))
                .frame(width: 80, height: 80)
                .blur(radius: 7)
        }
        .onChange(of: viewModel.mostRecentSelection) { _ in
            if viewModel.mostRecentSelection == self.index {
                triggerGlow()
            }
        }
        .background {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .preference(key: CardPreferenceKey.self,
                                value: [CardPreferenceData(index: self.index, bounds: geometry.frame(in: .named("GridSpace")))])
            }
        }
    }

    public func triggerGlow() {
        isBeingTouched = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isBeingTouched = false
            }
        }
    }
}

public struct CardPreferenceData: Equatable {
    public let index: Int
    public let bounds: CGRect
}

public struct CardPreferenceKey: PreferenceKey {
    public typealias Value = [CardPreferenceData]

    public static var defaultValue: [CardPreferenceData] = []

    public static func reduce(value: inout [CardPreferenceData], nextValue: () -> [CardPreferenceData]) {
        value.append(contentsOf: nextValue())
    }
}

// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI

/// A SwiftUI 3x3 gesture grid for pattern setup and authentication.
@MainActor
public struct GridAuthenticator: View {
    /// The main-actor view model that owns gesture flow state.
    @ObservedObject public var viewModel: GridAuthenticatorViewModel

    /// Creates a grid authenticator view for setup or authentication.
    ///
    /// - Parameter gridAuthModel: The setup or authentication option used to
    ///   configure the backing view model.
    /// - Returns: A SwiftUI view that presents the gesture grid.
    /// - Throws: This initializer does not throw.
    public init(_ gridAuthModel: GridAuthenticatorViewModel.GridAuthenticatorOption) {
        viewModel = GridAuthenticatorViewModel(gridAuthModel)
    }

    let columns = Array(repeating: GridItem(.fixed(60), spacing: 40), count: 3)

    public var body: some View {
        VStack {
            if viewModel.debug {
                Text("[DEBUG] Selected Vertices: \(viewModel.selectedCardsIndices.count)")
                    .padding()
                if viewModel.expectedCredential != nil {
                    Text("[DEBUG] Credential Mode: v1 envelope")
                        .padding()
                } else if viewModel.expectedHash != nil {
                    Text("[DEBUG] Credential Mode: legacy hash")
                        .padding()
                }
            }
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(0 ..< 9, id: \.self) { index in
                    GlowyCircle(index: index, viewModel: viewModel)
                        .padding()
                        .tag(index)
                }
            }
            .overlay {
                TimelineView(.animation) { timeline in
                    Canvas { context, _ in
                        let timelineDate = timeline.date.timeIntervalSinceReferenceDate
                        viewModel.particleSystem.update(date: timelineDate)

                        context.blendMode = .plusLighter
                        context.addFilter(.colorMultiply(viewModel.viewColor))
                        for particle in viewModel.particleSystem.particles {
                            let age = timelineDate - particle.creationDate
                            let opacity = max(0, 1 - age / viewModel.particleSystem.particleLifetime)
                            let particleDiameter = viewModel.particleSystem.particleDiameter
                            let particleRect = CGRect(
                                x: particle.x - particleDiameter / 2,
                                y: particle.y - particleDiameter / 2,
                                width: particleDiameter,
                                height: particleDiameter
                            )
                            context.opacity = opacity
                            context.draw(
                                viewModel.particleSystem.image,
                                in: particleRect
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .onPreferenceChange(CardPreferenceKey.self) { value in
                viewModel.cardsData = value
            }
            .coordinateSpace(name: "GridSpace")
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("GridSpace"))
                    .onChanged { drag in
                        viewModel.duringDrag(drag: drag)
                    }
                    .onEnded { _ in
                        viewModel.afterDrag()
                    }
            )

            VStack {
                Text(viewModel.validityText)
                    .foregroundStyle(.red)
                    .padding(.bottom)
                if viewModel.mode == .set {
                    switch viewModel.confirmationState {
                    case .initial:
                        Text("Set your pattern")
                            .foregroundStyle(viewModel.viewColor)
                            .padding(.bottom)
                    case .awaitingConfirmation:
                        Text("Please confirm your pattern")
                            .foregroundStyle(viewModel.viewColor)
                            .padding(.bottom)
                    case .confirmed:
                        Text("Pattern confirmed!")
                            .foregroundStyle(.green)
                            .padding(.bottom)
                    }
                    if viewModel.selectedCardsIndices.count > 0 && viewModel.locked {
                        HStack {
                            Button {
                                viewModel.reset()
                            } label: {
                                Text("Reset")
                                .bold()
                                .foregroundStyle(.red)
                            }
                            .buttonBorderShape(.capsule)
                            .buttonStyle(BorderedProminentButtonStyle())
                            .tint(.yellow)
                            .padding(.leading)
                            Spacer()
                            if viewModel.requireConfirmation ?? false && viewModel.confirmationState == .initial {
                                Button {
                                    viewModel.confirmPattern()
                                } label: {
                                    Text("Confirm")
                                }
                                .buttonBorderShape(.capsule)
                                .buttonStyle(BorderedProminentButtonStyle())
                                .tint(viewModel.viewColor)
                                .padding(.trailing)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
            }
        }
        .modifier(Shake(animatableData: CGFloat(viewModel.incorrectCount)))
    }
}

/// A single selectable circle in the 3x3 gesture grid.
@MainActor
public struct GlowyCircle: View {
    /// The zero-based 3x3 grid index represented by this circle.
    public var index: Int

    /// Whether the selection glow is currently visible.
    @State public var isBeingTouched: Bool = false

    /// The view model that receives geometry and selection updates.
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

    /// Temporarily highlights the circle after it is selected.
    ///
    /// The method does not return a value. It toggles ``isBeingTouched`` and
    /// animates it back to `false`.
    /// - Throws: This method does not throw.
    public func triggerGlow() {
        isBeingTouched = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isBeingTouched = false
            }
        }
    }
}

/// Geometry captured for one gesture grid circle.
public struct CardPreferenceData: Equatable, Sendable {
    /// The zero-based 3x3 grid index for the circle.
    public let index: Int

    /// The circle bounds in the named grid coordinate space.
    public let bounds: CGRect

    /// Creates captured geometry for a gesture grid circle.
    ///
    /// - Parameters:
    ///   - index: The zero-based 3x3 grid index.
    ///   - bounds: The circle bounds in the named grid coordinate space.
    /// - Returns: A geometry record used by the view model for hit testing and
    ///   path rendering.
    /// - Throws: This initializer does not throw.
    public init(index: Int, bounds: CGRect) {
        self.index = index
        self.bounds = bounds
    }
}

/// Aggregates grid circle geometry emitted by SwiftUI preferences.
public struct CardPreferenceKey: PreferenceKey {
    /// The preference value type.
    public typealias Value = [CardPreferenceData]

    /// The default preference value before any circles report geometry.
    public static let defaultValue: [CardPreferenceData] = []

    /// Appends newly reported circle geometry to the current preference value.
    ///
    /// - Parameters:
    ///   - value: The accumulated preference value to mutate.
    ///   - nextValue: A closure returning the next batch of geometry values.
    /// The method does not return a value. It mutates `value` in place.
    /// - Throws: This method does not throw.
    public static func reduce(value: inout [CardPreferenceData], nextValue: () -> [CardPreferenceData]) {
        value.append(contentsOf: nextValue())
    }
}

#if DEBUG
struct GridAuthenticatorPreviews: PreviewProvider {
    static var previews: some View {
        GridAuthenticator(.setCredential(debug: true) { _ in })
            .previewDisplayName("Credential Setup")
    }
}
#endif

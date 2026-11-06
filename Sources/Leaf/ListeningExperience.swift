import SwiftUI

struct ListeningExperience: View {
    @ObservedObject var reader: ReaderModel

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { reader.dismissListeningView() }
            cornerOrnaments
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(reader.book.title.uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(green.opacity(0.78))
                    Text(reader.chapter.title)
                        .font(.system(size: 19, weight: .medium, design: .serif))
                }
                .padding(.top, 44)
                Spacer(minLength: 24)
                Text(reader.listeningSentence)
                    .id(reader.listeningSentenceID)
                    .font(.system(size: sentenceFontSize, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(12)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: 1_000, maxHeight: .infinity)
                    .padding(.horizontal, 80)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeInOut(duration: 0.28), value: reader.listeningSentenceID)
                Spacer(minLength: 24)
                HStack(spacing: 16) {
                    Image(systemName: reader.isReading ? "speaker.wave.2.fill" : "pause.circle.fill")
                    Text(reader.isReading ? "Listening" : "Paused")
                    Text("← / → previous / next sentence")
                    Text("Click anywhere or press F5 to exit listening view").opacity(0.72)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(green.opacity(0.86))
                .padding(.bottom, 34)
            }
            .contentShape(Rectangle())
        }
        .onTapGesture { reader.dismissListeningView() }
        .onExitCommand { reader.dismissListeningView() }
    }

    private var cornerOrnaments: some View {
        ZStack {
            ornament("leaf.fill", alignment: .topLeading, rotation: -25)
            ornament("leaf.fill", alignment: .topTrailing, rotation: 35)
            ornament("sparkles", alignment: .bottomLeading, rotation: 0)
            ornament("sparkles", alignment: .bottomTrailing, rotation: 0)
        }
        .allowsHitTesting(false)
    }

    private func ornament(_ name: String, alignment: Alignment, rotation: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: 54, weight: .ultraLight))
            .foregroundStyle(green.opacity(0.12))
            .rotationEffect(.degrees(rotation))
            .padding(42)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var sentenceFontSize: CGFloat {
        switch reader.listeningSentence.count {
        case ..<90: return 64
        case ..<170: return 52
        case ..<280: return 42
        default: return 34
        }
    }
}

import Foundation

public enum SentenceNavigation {
    public struct Destination: Equatable {
        public let chapter: Int
        public let offset: Int
    }

    /// Move one sentence from the current speech position, crossing chapter
    /// boundaries and ignoring chapters without speakable text.
    public static func destination(in chapters: [Chapter], chapter: Int, offset: Int, direction: Int) -> Destination? {
        guard chapters.indices.contains(chapter), direction != 0 else { return nil }
        let step = direction > 0 ? 1 : -1
        let sentences = CloudAlignment.sentenceRanges(chapters[chapter].text)
        if !sentences.isEmpty {
            let current = sentences.firstIndex(where: { NSMaxRange($0) > offset }) ?? sentences.count - 1
            let next = current + step
            if sentences.indices.contains(next) {
                return Destination(chapter: chapter, offset: sentences[next].location)
            }
        }
        var nextChapter = chapter + step
        while chapters.indices.contains(nextChapter) {
            let ranges = CloudAlignment.sentenceRanges(chapters[nextChapter].text)
            if let sentence = step > 0 ? ranges.first : ranges.last {
                return Destination(chapter: nextChapter, offset: sentence.location)
            }
            nextChapter += step
        }
        return nil
    }
}

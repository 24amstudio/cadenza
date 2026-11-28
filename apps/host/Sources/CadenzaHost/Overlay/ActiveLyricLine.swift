/// The line sung at a playback position, and the line after it. The active line is the last line that has started by then.
/// Lines are in time order.
enum ActiveLyricLine {
    static func at(_ positionMs: Int64, in lines: [LyricLine]) -> LyricLine? {
        lines.last { $0.startMs <= positionMs }
    }

    static func window(at positionMs: Int64, in lines: [LyricLine]) -> (current: LyricLine?, next: LyricLine?) {
        guard let index = lines.lastIndex(where: { $0.startMs <= positionMs }) else {
            return (nil, lines.first)
        }
        let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
        return (lines[index], next)
    }
}

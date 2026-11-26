import SwiftUI
import Combine

// ──────────────────────────────────────────────
// File Drop Model (matches HTML concept)
// ──────────────────────────────────────────────

struct FileDrop: Identifiable {
    let id = UUID()
    let name: String
    let sizeMB: Double
    let icon: String
    var pos: CGPoint          // normalized 0..1
    var vel: CGVector = .zero // normalized velocity
    var radius: CGFloat = 26  // base radius in points
    var phase: Double = 0
    var state: DropState = .idle
    var progress: Float = 0   // for transfer scene
    var stretch: CGFloat = 0  // 0..0.55

    enum DropState {
        case idle, wait, ring, pull, gone
    }
}

// ──────────────────────────────────────────────
// Sample Data (matches HTML SPECS)
// ──────────────────────────────────────────────

extension FileDrop {
    static let sampleFiles: [(String, String, Double)] = [
        ("Отпуск.heic", "🖼", 4.2),
        ("Договор.pdf", "📄", 1.3),
        ("Клип.mov", "🎬", 842),
        ("Трек.flac", "🎵", 31),
        ("Архив.zip", "📦", 268),
        ("Заметки.txt", "📝", 0.02),
        ("Слайды.key", "📊", 96)
    ]

    static func randomDrops(count: Int, in rect: CGRect) -> [FileDrop] {
        var drops: [FileDrop] = []
        var usedPositions: [CGPoint] = []

        for _ in 0..<count {
            let spec = sampleFiles.randomElement()!
            let r = 26 + 16 * CGFloat(log10(spec.2 * 1_000_000) - 3) / 6

            // Find position with max distance from existing (Poisson disk-ish)
            var bestPos = CGPoint(x: 0.5, y: 0.5)
            var bestDist: CGFloat = 0

            for _ in 0..<28 {
                let candidate = CGPoint(
                    x: CGFloat.random(in: 0.14...0.86),
                    y: CGFloat.random(in: 0.16...0.84)
                )
                let minDist = usedPositions.map { candidate.distance(to: $0) }.min() ?? 1.0
                if minDist > bestDist {
                    bestDist = minDist
                    bestPos = candidate
                }
            }

            usedPositions.append(bestPos)

            drops.append(FileDrop(
                name: spec.0,
                sizeMB: spec.2,
                icon: spec.1,
                pos: bestPos,
                phase: Double.random(in: 0...2 * .pi),
                radius: r
            ))
        }
        return drops
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

// ──────────────────────────────────────────────
// Formatters
// ──────────────────────────────────────────────

func formatSize(_ mb: Double) -> String {
    if mb < 1 { return "\(Int(mb * 1024)) КБ" }
    if mb < 1024 { return String(format: "%.1f МБ", mb).replacingOccurrences(of: ".", with: ",") }
    return String(format: "%.2f ГБ", mb / 1024).replacingOccurrences(of: ".", with: ",")
}

func pluralizeFiles(_ count: Int) -> String {
    let mod10 = count % 10
    let mod100 = count % 100
    if mod10 == 1 && mod100 != 11 { return "файл" }
    if [2, 3, 4].contains(mod10) && ![12, 13, 14].contains(mod100) { return "файла" }
    return "файлов"
}
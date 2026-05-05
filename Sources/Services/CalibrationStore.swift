import Foundation

/// Tracks confidence-vs-outcome data for metacognitive calibration charts.
/// Confidence: 1=No, 2=Unsure, 3=Yes (matches StudyView confidenceButton values).
enum CalibrationStore {

    struct Bucket: Codable {
        var correct: Int = 0
        var wrong: Int = 0
        var total: Int { correct + wrong }
        var accuracy: Double { total > 0 ? Double(correct) / Double(total) : 0 }
    }

    private static let key = "calibration.buckets.v1"

    static func record(confidence: Int, wasCorrect: Bool) {
        var buckets = load()
        var bucket = buckets[confidence] ?? Bucket()
        if wasCorrect { bucket.correct += 1 } else { bucket.wrong += 1 }
        buckets[confidence] = bucket
        save(buckets)
    }

    static func load() -> [Int: Bucket] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Bucket].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { k, v in
            Int(k).map { ($0, v) }
        })
    }

    static func hasEnoughData() -> Bool {
        load().values.reduce(0) { $0 + $1.total } >= 10
    }

    private static func save(_ buckets: [Int: Bucket]) {
        let stringKeyed = Dictionary(uniqueKeysWithValues: buckets.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

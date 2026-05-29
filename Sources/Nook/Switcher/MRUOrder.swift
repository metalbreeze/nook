import Foundation

/// Pure most-recently-used reordering, so the switcher lists apps like the
/// native Cmd+Tab: the apps you used most recently come first.
enum MRUOrder {
    /// Reorders `pids` by `recency` (most-recent-first). PIDs that appear in
    /// `recency` are emitted first, in recency order; PIDs not in `recency` keep
    /// their original relative order and are appended after.
    static func ordered(_ pids: [pid_t], byRecency recency: [pid_t]) -> [pid_t] {
        let pidSet = Set(pids)
        var known: [pid_t] = []
        var knownSet = Set<pid_t>()
        for pid in recency where pidSet.contains(pid) && knownSet.insert(pid).inserted {
            known.append(pid)
        }
        let rest = pids.filter { !knownSet.contains($0) }
        return known + rest
    }
}

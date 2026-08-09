import Foundation

// 从自然语言里解析到期时间（中文/英文），供快速创建任务时自动调度本地提醒。
// 无匹配时返回 nil（保持原行为：不调度通知）。
enum DueDateParser {
    static func parse(from text: String, now: Date = Date()) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // 1) 相对日：今天/今晚/今日、明天、后天 —— 有具体时刻用时刻，否则兜底当日 23:59
        if hasToken(lower, "后天") {
            return resolveClock(in: lower, at: dayBase(2, now))
                ?? endOfDay(dayBase(2, now))
        }
        if hasToken(lower, "明天") || hasToken(lower, "明早") || hasToken(lower, "明晚") {
            return resolveClock(in: lower, at: dayBase(1, now))
                ?? endOfDay(dayBase(1, now))
        }
        if hasToken(lower, "今天") || hasToken(lower, "今晚") || hasToken(lower, "今日") {
            return resolveClock(in: lower, at: now)
                ?? endOfDay(now)
        }

        // 2) 时段词（下午/晚上/中午/上午/凌晨）→ 今天对应时刻，12 小时制自动 +12
        if hasToken(lower, "下午") || hasToken(lower, "晚上") || hasToken(lower, "中午")
            || hasToken(lower, "上午") || hasToken(lower, "凌晨") {
            if let date = resolveClock(in: lower, at: now), date > now {
                return date
            }
        }

        // 3) X 小时后 / X 分钟后
        if let h = firstCapture(before: "小时", in: lower) {
            return now.addingTimeInterval(TimeInterval(h) * 3600)
        }
        if let m = firstCapture(before: "分钟", in: lower) {
            return now.addingTimeInterval(TimeInterval(max(1, m)) * 60)
        }

        // 4) 裸时刻：3点 / 15:30 / 下午2点
        if let date = resolveClock(in: lower, at: now), date > now {
            return date
        }
        return nil
    }

    // MARK: - helpers

    private static func dayBase(_ daysFromToday: Int, _ now: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromToday, to: now) ?? now
    }

    private static func endOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date).addingTimeInterval(24 * 3600 - 1)
    }

    // 在 base 所在日的 00:00 上叠加时刻；时段词自动调 12 小时制
    private static func resolveClock(in lower: String, at base: Date) -> Date? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: base)
        if let clock = parseClock(from: lower) {
            return cal.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: dayStart)
        }
        if let hour = parseHour(from: lower) {
            let phase12 = (hasToken(lower, "下午") || hasToken(lower, "晚上") || hasToken(lower, "中午")) && hour < 12
            let hour24 = phase12 ? hour + 12 : hour
            return cal.date(bySettingHour: hour24, minute: 0, second: 0, of: dayStart)
        }
        return nil
    }

    private static func hasToken(_ text: String, _ token: String) -> Bool {
        text.range(of: token) != nil
    }

    // 中文"X点/X时"（容忍"3点/03点/3时/15点"）
    private static func parseHour(from text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[点时]"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: text),
              let hour = Int(String(text[swiftRange])),
              (1...23).contains(hour) else { return nil }
        return hour
    }

    // "3:30" / "15:00" 裸时刻
    private static func parseClock(from text: String) -> (hour: Int, minute: Int)? {
        guard let m = regexMatch(#"\d{1,2}:\d{2}"#, in: text) else { return nil }
        let parts = m.components(separatedBy: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private static func regexMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 0), in: text) else { return nil }
        return String(text[swiftRange])
    }

    // 提取"X小时后/X分钟前"里的纯数字，要求紧跟单位词后再补"后"
    private static func firstCapture(before unit: String, in text: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: unit)
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*"# + escaped + #"\s*后"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range(at: 1), in: text),
              let value = Int(String(text[swiftRange])) else { return nil }
        return value
    }
}

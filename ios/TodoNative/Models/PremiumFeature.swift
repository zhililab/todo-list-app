import Foundation

enum PremiumFeature: String, CaseIterable, Identifiable {
    case aiPlan = "AI 今日计划"
    case advancedExporter = "高级导出"
    case taskTemplate = "任务模板"
    case analyticsBoard = "分析看板"
    case themePack = "主题包"

    var id: String { rawValue }
}

enum TrialState {
    case free
    case trial(remainingDays: Int)
    case premium
}

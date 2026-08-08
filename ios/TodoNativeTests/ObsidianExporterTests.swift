import XCTest
@testable import TodoNative

final class ObsidianExporterTests: XCTestCase {
    private func makeItem(
        title: String,
        status: TodoStatus = .todo,
        context: String = "",
        criteria: String = "",
        prompt: String = "",
        isArchived: Bool = false
    ) -> TodoItem {
        let item = TodoItem(
            title: title,
            context: context,
            acceptanceCriteria: criteria,
            nextPrompt: prompt,
            taskType: .life,
            status: status,
            isArchived: isArchived
        )
        return item
    }

    func testFileNameUsesDateKey() {
        let date = dateAtNoon(day: 8, month: 8, year: 2026)
        XCTAssertEqual(ObsidianExporter.fileName(date: date), "todo-list-app-2026-08-08.md")
    }

    func testMarkdownContainsHeader() {
        let date = dateAtNoon(day: 8, month: 8, year: 2026)
        let md = ObsidianExporter.makeDailyMarkdown(for: [], date: date)
        XCTAssertTrue(md.contains("# TodoList 每日导出 2026-08-08"))
        XCTAssertTrue(md.contains("2026-08-08"))
    }

    private func dateAtNoon(day: Int, month: Int, year: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        components.hour = 12
        return Calendar.current.date(from: components)!
    }

    func testPendingItemsRenderedAsCheckboxes() {
        let items = [makeItem(title: "写文档", context: "仓库", criteria: "合并", prompt: "下一条")]
        let md = ObsidianExporter.makeDailyMarkdown(for: items)
        XCTAssertTrue(md.contains("- [ ] 写文档 （生活）"))
        XCTAssertTrue(md.contains("上下文：仓库"))
        XCTAssertTrue(md.contains("验收标准：合并"))
        XCTAssertTrue(md.contains("下一步提示：下一条"))
    }

    func testCompletedItemsRenderedAsChecked() {
        let items = [makeItem(title: "完成的需求", status: .done)]
        let md = ObsidianExporter.makeDailyMarkdown(for: items)
        XCTAssertTrue(md.contains("- [x] 完成的需求 （生活）"))
        XCTAssertTrue(md.contains("## 已完成任务"))
    }

    func testEmptyContextSkipped() {
        let items = [makeItem(title: "基础任务")]
        let md = ObsidianExporter.makeDailyMarkdown(for: items)
        XCTAssertFalse(md.contains("上下文"))
    }

    func testArchivedItemsExcluded() {
        let items = [makeItem(title: "归档项", isArchived: true)]
        let md = ObsidianExporter.makeDailyMarkdown(for: items)
        XCTAssertFalse(md.contains("归档项"))
    }

    func testBothPendingAndCompletedSections() {
        let items = [
            makeItem(title: "进行中任务", status: .doing),
            makeItem(title: "已完成任务", status: .done)
        ]
        let md = ObsidianExporter.makeDailyMarkdown(for: items)
        XCTAssertTrue(md.contains("## 未完成任务"))
        XCTAssertTrue(md.contains("## 已完成任务"))
    }
}
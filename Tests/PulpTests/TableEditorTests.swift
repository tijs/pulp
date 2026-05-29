import Foundation
@testable import Pulp
import Testing

@Suite("TableEditor")
struct TableEditorTests {
    @Test func templateDimensions() {
        let table = TableEditor.template(rows: 2, columns: 3)
        let lines = table.split(separator: "\n").map(String.init)
        // header + separator + 2 data rows
        #expect(lines.count == 4)
        let parsed = TableEditor.parse(table)
        #expect(parsed?.columnCount == 3)
        #expect(parsed?.rows.count == 2)
    }

    @Test func parseRoundTrip() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let parsed = TableEditor.parse(md)
        #expect(parsed?.header == ["A", "B"])
        #expect(parsed?.rows == [["1", "2"]])
    }

    @Test func insertRowAfterFirst() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let result = TableEditor.insertRow(in: md, afterDataRowIndex: 0)
        let parsed = TableEditor.parse(result)
        #expect(parsed?.rows.count == 2)
        #expect(parsed?.rows[0] == ["1", "2"])
        #expect(parsed?.rows[1] == ["", ""])
    }

    @Test func insertRowAtTop() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let result = TableEditor.insertRow(in: md, afterDataRowIndex: -1)
        let parsed = TableEditor.parse(result)
        #expect(parsed?.rows.count == 2)
        #expect(parsed?.rows[0] == ["", ""])
        #expect(parsed?.rows[1] == ["1", "2"])
    }

    @Test func deleteRow() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |"
        let result = TableEditor.deleteRow(in: md, dataRowIndex: 0)
        let parsed = TableEditor.parse(result)
        #expect(parsed?.rows == [["3", "4"]])
    }

    @Test func insertColumn() {
        let md = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let result = TableEditor.insertColumn(in: md, afterColumnIndex: 0)
        let parsed = TableEditor.parse(result)
        #expect(parsed?.columnCount == 3)
        #expect(parsed?.header == ["A", "Column", "B"])
        #expect(parsed?.rows[0] == ["1", "", "2"])
    }

    @Test func deleteColumn() {
        let md = "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |"
        let result = TableEditor.deleteColumn(in: md, columnIndex: 1)
        let parsed = TableEditor.parse(result)
        #expect(parsed?.columnCount == 2)
        #expect(parsed?.header == ["A", "C"])
        #expect(parsed?.rows[0] == ["1", "3"])
    }

    @Test func cannotDeleteLastColumn() {
        let md = "| A |\n| --- |\n| 1 |"
        let result = TableEditor.deleteColumn(in: md, columnIndex: 0)
        #expect(result == md)
    }
}

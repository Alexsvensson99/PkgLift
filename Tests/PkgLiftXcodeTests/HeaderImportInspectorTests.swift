import Darwin
import Foundation
import XCTest
@testable import PkgLiftXcode

final class HeaderImportInspectorTests: XCTestCase {
    func testQualifiedAndNestedQuotedImportsAreClearWhileFlatImportsNeedReview() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try write("#import <Foundation/Foundation.h>\n#import <SDWebImage/SDWebImage.h>\n#import \"Nested.h\"\n", at: root.appendingPathComponent("Main.h"))
        try write("// #import <stdio.h>\n#import \"Leaf.h\"\n", at: root.appendingPathComponent("Nested.h"))
        try write("#include <SDWebImage/SDImageCache.h>\n", at: root.appendingPathComponent("Leaf.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Main.h")], root: root), .clear)
        try write("#include <stdio.h>\n", at: root.appendingPathComponent("Flat.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Flat.h")], root: root), .requiresReview)
    }

    func testMissingQuotedImportAndCommentsAreHandledConservatively() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try write("/* #import <stdio.h> */\n// #include <stdio.h>\n#import \"Missing.h\"\n", at: root.appendingPathComponent("Main.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Main.h")], root: root), .requiresReview)
        try write("#include HEADER_MACRO\n", at: root.appendingPathComponent("Macro.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Macro.h")], root: root), .incomplete)
    }

    func testLexicallyValidCompactAndCommentSeparatedIncludesAreInspected() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try write("#include<SDImageCache.h>\n", at: root.appendingPathComponent("Compact.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Compact.h")], root: root), .requiresReview)
        try write("#include/**/<SDImageCache.h>\n", at: root.appendingPathComponent("CommentSeparated.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("CommentSeparated.h")], root: root), .requiresReview)
        try write("#import\"Nested.h\"\r", at: root.appendingPathComponent("Quoted.h"))
        try write("#include\\\r\n<SDImageCache.h>\r", at: root.appendingPathComponent("Nested.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Quoted.h")], root: root), .requiresReview)
    }

    func testUnsupportedAndUnsafeDirectiveFormsAreIncomplete() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let cases = [
            "#include_next <SDImageCache.h>\n",
            "%:include <SDImageCache.h>\n",
            "#include </SDImageCache.h>\n",
            "#include <../SDImageCache.h>\n",
            "#include <./SDImageCache.h>\n",
            "#include <SDWebImage\\SDImageCache.h>\n",
            "#include <<SDImageCache.h>>\n"
        ]
        for (index, source) in cases.enumerated() {
            let file = root.appendingPathComponent("Unsafe-\(index).h")
            try write(source, at: file)
            XCTAssertEqual(HeaderImportInspector().inspect(files: [file], root: root), .incomplete, "case \(index)")
        }
        let nulQuoted = root.appendingPathComponent("NULQuoted.h")
        try write(Data([35, 105, 109, 112, 111, 114, 116, 32, 34, 66, 97, 100, 0, 46, 104, 34, 10]), at: nulQuoted)
        XCTAssertEqual(HeaderImportInspector().inspect(files: [nulQuoted], root: root), .incomplete)
        let nulAngle = root.appendingPathComponent("NULAngle.h")
        try write(Data([35, 105, 110, 99, 108, 117, 100, 101, 32, 60, 66, 97, 100, 0, 46, 104, 62, 10]), at: nulAngle)
        XCTAssertEqual(HeaderImportInspector().inspect(files: [nulAngle], root: root), .incomplete)
    }

    func testBOMHeaderUnitsAndUnsafePrimaryPathsAreIncomplete() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let bom = root.appendingPathComponent("BOM.h")
        try write(Data([0xEF, 0xBB, 0xBF, 35, 105, 110, 99, 108, 117, 100, 101, 32, 60, 70, 111, 111, 46, 104, 62, 10]), at: bom)
        XCTAssertEqual(HeaderImportInspector().inspect(files: [bom], root: root), .incomplete)
        try write("int value = 0; import <Flat.h>;\n", at: root.appendingPathComponent("HeaderUnit.h"))
        try write("export import \"Local.h\";\n", at: root.appendingPathComponent("ExportHeaderUnit.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("HeaderUnit.h")], root: root), .incomplete)
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("ExportHeaderUnit.h")], root: root), .incomplete)
        let nulPath = root.appendingPathComponent("Bad\u{0}.h")
        XCTAssertEqual(HeaderImportInspector().inspect(files: [nulPath], root: root), .incomplete)
    }

    func testIndependentInputsAndBoundsAccumulateConservatively() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let invalid = root.appendingPathComponent("Invalid.h")
        let flat = root.appendingPathComponent("Flat.h")
        try write("#include HEADER_MACRO\n", at: invalid)
        try write("#include <Flat.h>\n", at: flat)
        let inspector = HeaderImportInspector()
        XCTAssertEqual(inspector.inspect(files: [invalid, flat], root: root), .requiresReview)
        XCTAssertEqual(inspector.inspect(files: [flat, invalid], root: root), .requiresReview)

        var manyFiles: [URL] = []
        for index in 0...512 {
            let file = root.appendingPathComponent("Count-\(index).h")
            try write("\n", at: file)
            manyFiles.append(file)
        }
        XCTAssertEqual(inspector.inspect(files: manyFiles, root: root), .incomplete)

        var totalFiles: [URL] = []
        let oneMiB = String(repeating: " ", count: 1_024 * 1_024)
        for index in 0..<17 {
            let file = root.appendingPathComponent("Total-\(index).h")
            try write(oneMiB, at: file)
            totalFiles.append(file)
        }
        XCTAssertEqual(inspector.inspect(files: totalFiles, root: root), .incomplete)

        for index in 0...33 {
            let source = index == 33 ? "\n" : "#import \"Depth-\(index + 1).h\"\n"
            try write(source, at: root.appendingPathComponent("Depth-\(index).h"))
        }
        XCTAssertEqual(inspector.inspect(files: [root.appendingPathComponent("Depth-0.h")], root: root), .incomplete)
    }

    func testEscapesSymlinksAndNonRegularInputsAreIncomplete() throws {
        let root = try makeRoot(); let outside = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try write("#import \"../Outside.h\"\n", at: root.appendingPathComponent("Escape.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Escape.h")], root: root), .incomplete)
        try write("#import <Foundation/Foundation.h>\n", at: outside.appendingPathComponent("Outside.h"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Link.h"), withDestinationURL: outside.appendingPathComponent("Outside.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Link.h")], root: root), .incomplete)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Directory.h"), withIntermediateDirectories: true)
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Directory.h")], root: root), .incomplete)
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("Headers"), withIntermediateDirectories: true)
        try write("#import <Foundation/Foundation.h>\n", at: outside.appendingPathComponent("Headers/Child.h"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Headers"), withDestinationURL: outside.appendingPathComponent("Headers"))
        try write("#import \"Headers/Child.h\"\n", at: root.appendingPathComponent("Parent.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Parent.h")], root: root), .incomplete)
        let fifo = root.appendingPathComponent("Pipe.h")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertEqual(HeaderImportInspector().inspect(files: [fifo], root: root), .incomplete)
    }

    func testCyclesAndBoundsTerminateWithoutReadingBeyondPolicy() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try write("#import \"B.h\"\n", at: root.appendingPathComponent("A.h"))
        try write("#import \"A.h\"\n", at: root.appendingPathComponent("B.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("A.h")], root: root), .clear)
        try write(String(repeating: "x", count: 1_024 * 1_024 + 1), at: root.appendingPathComponent("Large.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Large.h")], root: root), .incomplete)
        try write("", at: root.appendingPathComponent("Empty.h"))
        XCTAssertEqual(HeaderImportInspector().inspect(files: [root.appendingPathComponent("Empty.h")], root: root), .clear)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ value: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }

    private func write(_ value: Data, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: url)
    }
}

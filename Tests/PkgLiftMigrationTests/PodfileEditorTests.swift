//
//  PodfileEditorTests.swift
//  PkgLiftMigrationTests
//

import XCTest
@testable import PkgLiftMigration

final class PodfileEditorTests: XCTestCase {
    func testRemovesAllSupportedFormsAndPreservesCommentsDataAndCRLF() {
        let original = """
        # pod 'Alamofire' is mentioned in a comment
        =begin
        pod 'Alamofire'
        =end
        target 'App' do
          pod 'Alamofire'
          pod('Alamofire')
          pod\t'Alamofire' # actual declaration
          pod 'SnapKit'
        end
        __END__
        pod 'Alamofire'

        """.replacingOccurrences(of: "\n", with: "\r\n")
        let expected = """
        # pod 'Alamofire' is mentioned in a comment
        =begin
        pod 'Alamofire'
        =end
        target 'App' do
          pod 'SnapKit'
        end
        __END__
        pod 'Alamofire'

        """.replacingOccurrences(of: "\n", with: "\r\n")
        let result = PodfileEditor().removeWithResult(pods: ["Alamofire"], from: original)
        XCTAssertEqual(result.content, expected)
        XCTAssertEqual(result.removedPods, ["Alamofire"])
    }

    func testRemoveSinglePod() {
        let editor = PodfileEditor()
        let podfile = """
        target 'MyApp' do
          pod 'Alamofire', '~> 5.0'
          pod 'SwiftyJSON', '~> 4.0'
        end
        """
        
        let result = editor.remove(pods: ["Alamofire"], from: podfile)
        XCTAssertFalse(result.contains("pod 'Alamofire'"))
        XCTAssertTrue(result.contains("pod 'SwiftyJSON'"))
        XCTAssertTrue(result.contains("target 'MyApp' do"))
    }
    
    func testRemovingLastPodPreservesTargetAndUnrelatedRuby() {
        let editor = PodfileEditor()
        let podfile = """
        target 'MyApp' do
          use_frameworks!
          pod 'Alamofire', '~> 5.0'
          script_phase :name => 'Owned by app'
        end
        """
        
        let result = editor.remove(pods: ["Alamofire"], from: podfile)
        XCTAssertFalse(result.contains("pod 'Alamofire'"))
        XCTAssertTrue(result.contains("target 'MyApp' do"))
        XCTAssertTrue(result.contains("use_frameworks!"))
        XCTAssertTrue(result.contains("script_phase"))
        XCTAssertTrue(result.contains("end"))
    }

    func testSimilarAndSubspecNamesAreNotRemoved() {
        let podfile = """
        target 'MyApp' do
          pod 'Firebase'
          pod 'FirebaseAnalytics'
          pod 'Firebase/Analytics'
        end
        """

        let result = PodfileEditor().remove(pods: ["Firebase/Analytics"], from: podfile)
        XCTAssertTrue(result.contains("pod 'Firebase'"))
        XCTAssertTrue(result.contains("pod 'FirebaseAnalytics'"))
        XCTAssertFalse(result.contains("pod 'Firebase/Analytics'"))
    }

    func testEditResultReportsMissingDeclarationWithoutMutation() {
        let podfile = "target 'App' do\n  pod 'SnapKit'\nend"
        let result = PodfileEditor().removeWithResult(pods: ["Alamofire"], from: podfile)

        XCTAssertEqual(result.content, podfile)
        XCTAssertTrue(result.removedPods.isEmpty)
    }
}

import Foundation
import XCTest
@testable import PkgLiftCore

final class SourceProvenanceTests: XCTestCase {
    private let checkoutCommit = String(repeating: "a", count: 40)

    func testCanonicalizationKeepsHTTPSTransportSeparateAndUnifiesSSHWithSCP() throws {
        let https = GitRepositoryCanonicalizer.evidence(
            for: "https://GitHub.COM/Owner/Repo.git/"
        )
        let ssh = GitRepositoryCanonicalizer.evidence(
            for: "ssh://git@GITHUB.com/Owner/Repo.git"
        )
        let scp = GitRepositoryCanonicalizer.evidence(
            for: "git@github.com:Owner/Repo.git"
        )

        XCTAssertEqual(https.identity?.value, "https://github.com/Owner/Repo")
        XCTAssertEqual(ssh.identity?.value, "ssh://github.com/Owner/Repo")
        XCTAssertEqual(scp.identity, ssh.identity)
        XCTAssertNotEqual(https.identity, ssh.identity)
        XCTAssertEqual(https.status, .supported)
        XCTAssertEqual(ssh.status, .supported)
        XCTAssertEqual(scp.status, .supported)
        XCTAssertEqual(scp.syntax, .scp)

        let encodedSSH = try JSONEncoder().encode(ssh)
        XCTAssertEqual(
            try JSONDecoder().decode(GitRepositoryEvidence.self, from: encodedSSH),
            ssh
        )
    }

    func testCanonicalizationRedactsCredentialQueryAndFragmentWithoutRetainingRawValues() throws {
        let secretURL = "https://alice:password@example.com/Owner/Repo.git?token=secret#private"
        let evidence = GitRepositoryCanonicalizer.evidence(for: secretURL)

        XCTAssertEqual(evidence.identity?.value, "https://example.com/Owner/Repo")
        XCTAssertEqual(evidence.displayURL, "https://example.com/Owner/Repo")
        XCTAssertEqual(evidence.status, .credentialBearing)
        XCTAssertTrue(evidence.containedCredentialMaterial)

        let encoded = try JSONEncoder().encode(evidence)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for secret in ["alice", "password", "token", "secret", "private"] {
            XCTAssertFalse(json.contains(secret))
        }

        let scp = GitRepositoryCanonicalizer.evidence(
            for: "git@example.com:Owner/Repo.git?token=secret#private"
        )
        XCTAssertEqual(scp.identity?.value, "ssh://example.com/Owner/Repo")
        XCTAssertEqual(scp.status, .credentialBearing)
        XCTAssertFalse(scp.displayURL.contains("token"))
    }

    func testCanonicalizationRejectsUnsupportedBoundaries() {
        let rejected = [
            "http://example.com/Owner/Repo.git",
            "git://example.com/Owner/Repo.git",
            "https://example.com:8443/Owner/Repo.git",
            "ssh://git@example.com:2222/Owner/Repo.git",
            "https://example.com/Owner/../Repo.git",
            "https://example.com/Owner%2FRepo.git",
            "https://example.com/Owner/%2e%2e/Repo.git",
            "https://example.com//Owner/Repo.git",
            "ssh://example.com/Owner/Repo.git",
            "ssh://deploy@example.com/Owner/Repo.git",
            "git@example.com:/Owner/Repo.git",
        ]

        for literal in rejected {
            let evidence = GitRepositoryCanonicalizer.evidence(for: literal)
            XCTAssertEqual(evidence.status, .unsupportedURL, literal)
            XCTAssertNil(evidence.identity, literal)
            XCTAssertEqual(evidence.displayURL, GitRepositoryEvidence.redactedDisplayURL)
        }
    }

    func testInvalidStructuralSCPDoesNotInventCredentialEvidence() {
        for literal in [
            "git@example.com:/Owner/Repo.git",
            "git@bad_host:Owner/Repo.git",
            "git@example.com:Owner/Repo.git ",
            "git@example.com:Owner%2FRepo.git",
        ] {
            let repository = GitRepositoryCanonicalizer.evidence(for: literal)
            XCTAssertEqual(repository.status, .unsupportedURL, literal)
            XCTAssertFalse(repository.containedCredentialMaterial, literal)
            XCTAssertEqual(
                GitSourceProvenance(declarations: [
                    GitDeclarationEvidence(repository: repository, reference: .unpinned),
                ]).status,
                .unsupportedURL,
                literal
            )
        }
    }

    func testRepositorySuffixPolicyIsCaseSensitiveAndCanonicalOutputIsIdempotent() throws {
        let mixedCase = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Owner/Repo.GIT"
        )
        let transportSuffix = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Owner/Repo.git"
        )
        let repeatedSuffix = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Owner/Repo.git.git"
        )
        let slashSeparatedSuffix = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Owner/Repo.git/.git"
        )

        XCTAssertEqual(mixedCase.identity?.value, "https://example.com/Owner/Repo.GIT")
        XCTAssertEqual(transportSuffix.identity?.value, "https://example.com/Owner/Repo")
        XCTAssertNotEqual(mixedCase.identity, transportSuffix.identity)
        XCTAssertEqual(repeatedSuffix.status, .unsupportedURL)
        XCTAssertNil(repeatedSuffix.identity)
        XCTAssertEqual(slashSeparatedSuffix.status, .unsupportedURL)
        XCTAssertNil(slashSeparatedSuffix.identity)
        XCTAssertEqual(
            try JSONDecoder().decode(
                GitRepositoryEvidence.self,
                from: JSONEncoder().encode(mixedCase)
            ),
            mixedCase
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                GitRepositoryEvidence.self,
                from: JSONEncoder().encode(slashSeparatedSuffix)
            ),
            slashSeparatedSuffix
        )
    }

    func testSingleComponentRepositoryPathIsAmbiguous() {
        let evidence = GitRepositoryCanonicalizer.evidence(for: "https://example.com/Repo.git")

        XCTAssertEqual(evidence.status, .ambiguousRepository)
        XCTAssertEqual(evidence.identity?.value, "https://example.com/Repo")
        XCTAssertNoThrow(try JSONDecoder().decode(
            GitRepositoryEvidence.self,
            from: JSONEncoder().encode(evidence)
        ))
    }

    func testReferenceFactoryRetainsOnlyBoundedSafeValues() throws {
        let branch = try XCTUnwrap(GitReferenceEvidence.make(kind: .branch, value: "release/v1"))
        let tag = try XCTUnwrap(GitReferenceEvidence.make(kind: .tag, value: "1.2.3"))
        let commit = try XCTUnwrap(GitReferenceEvidence.make(kind: .commit, value: checkoutCommit))
        let sha256Commit = try XCTUnwrap(GitReferenceEvidence.make(
            kind: .commit,
            value: String(repeating: "b", count: 64)
        ))

        XCTAssertEqual(branch.declaredStability, .mutable)
        XCTAssertEqual(tag.declaredStability, .declaredImmutable)
        XCTAssertEqual(commit.declaredStability, .declaredImmutable)
        XCTAssertTrue(commit.isFullCheckoutCommit)
        XCTAssertTrue(sha256Commit.isFullCheckoutCommit)
        XCTAssertEqual(GitReferenceEvidence.unpinned.declaredStability, .unpinned)

        for unsafe in [
            "main..next", "refs/@{upstream}", "bad ref", "topic.lock",
            "feature.lock/next", "../main", "@",
        ] {
            XCTAssertNil(GitReferenceEvidence.make(kind: .branch, value: unsafe))
        }
        XCTAssertNil(GitReferenceEvidence.make(kind: .commit, value: "not-a-commit"))
        XCTAssertNil(GitReferenceEvidence.make(
            kind: .commit,
            value: String(repeating: "Ｆ", count: 40)
        ))
        XCTAssertNil(GitReferenceEvidence.make(kind: .branch, value: "rélease"))
        XCTAssertNil(GitReferenceEvidence.make(kind: .branch, value: "re\u{301}lease"))
        XCTAssertNil(GitReferenceEvidence.make(
            kind: .branch,
            value: String(repeating: "a", count: 256)
        ))
        XCTAssertNil(GitReferenceEvidence.make(kind: .unpinned, value: "main"))
    }

    func testMutableAndUnpinnedStatusesDoNotDependOnLockfile() throws {
        let repository = GitRepositoryCanonicalizer.evidence(for: "https://example.com/Owner/Repo")
        let branch = try XCTUnwrap(GitReferenceEvidence.make(kind: .branch, value: "main"))

        XCTAssertEqual(
            GitSourceProvenance(declarations: [
                GitDeclarationEvidence(repository: repository, reference: branch),
            ]).status,
            .mutable
        )
        XCTAssertEqual(
            GitSourceProvenance(declarations: [
                GitDeclarationEvidence(repository: repository, reference: .unpinned),
            ]).status,
            .unpinned
        )
    }

    func testTagRequiresMatchingLockReferenceAndFullCheckoutCommit() throws {
        let repository = GitRepositoryCanonicalizer.evidence(for: "https://example.com/Owner/Repo")
        let tag = try XCTUnwrap(GitReferenceEvidence.make(kind: .tag, value: "1.2.3"))
        let commit = try XCTUnwrap(GitReferenceEvidence.make(kind: .commit, value: checkoutCommit))
        let declaration = GitDeclarationEvidence(repository: repository, reference: tag)

        let complete = GitSourceProvenance(
            declarations: [declaration],
            lockfile: GitLockfileEvidence(
                externalSourceRepository: repository,
                externalSourceReference: tag,
                checkoutRepository: repository,
                checkoutReference: commit
            )
        )
        XCTAssertEqual(complete.status, .supportedImmutable)

        let shortCommit = try XCTUnwrap(
            GitReferenceEvidence.make(kind: .commit, value: String(checkoutCommit.prefix(12)))
        )
        let incomplete = GitSourceProvenance(
            declarations: [declaration],
            lockfile: GitLockfileEvidence(
                externalSourceRepository: repository,
                externalSourceReference: tag,
                checkoutRepository: repository,
                checkoutReference: shortCommit
            )
        )
        XCTAssertEqual(incomplete.status, .incomplete)
    }

    func testDirectCommitMustExactlyMatchFullCheckoutCommit() throws {
        let repository = GitRepositoryCanonicalizer.evidence(for: "ssh://git@example.com/Owner/Repo")
        let declared = try XCTUnwrap(
            GitReferenceEvidence.make(kind: .commit, value: checkoutCommit)
        )
        let different = try XCTUnwrap(
            GitReferenceEvidence.make(kind: .commit, value: String(repeating: "b", count: 40))
        )

        let matching = GitSourceProvenance(
            declarations: [GitDeclarationEvidence(repository: repository, reference: declared)],
            lockfile: GitLockfileEvidence(
                externalSourceRepository: repository,
                externalSourceReference: declared,
                checkoutRepository: repository,
                checkoutReference: declared
            )
        )
        XCTAssertEqual(matching.status, .supportedImmutable)

        let mismatching = GitSourceProvenance(
            declarations: matching.declarations,
            lockfile: GitLockfileEvidence(
                externalSourceRepository: repository,
                externalSourceReference: declared,
                checkoutRepository: repository,
                checkoutReference: different
            )
        )
        XCTAssertEqual(mismatching.status, .conflicting)
    }

    func testRepositoryMismatchUnsupportedSyntaxAndCredentialStatusesFailClosed() throws {
        let https = GitRepositoryCanonicalizer.evidence(for: "https://example.com/Owner/Repo")
        let ssh = GitRepositoryCanonicalizer.evidence(for: "ssh://git@example.com/Owner/Repo")
        let credentialed = GitRepositoryCanonicalizer.evidence(
            for: "https://user:pass@example.com/Owner/Repo"
        )
        let tag = try XCTUnwrap(GitReferenceEvidence.make(kind: .tag, value: "1.0.0"))
        let commit = try XCTUnwrap(GitReferenceEvidence.make(kind: .commit, value: checkoutCommit))

        let conflict = GitSourceProvenance(
            declarations: [GitDeclarationEvidence(repository: https, reference: tag)],
            lockfile: GitLockfileEvidence(
                externalSourceRepository: ssh,
                externalSourceReference: tag,
                checkoutRepository: ssh,
                checkoutReference: commit
            )
        )
        XCTAssertEqual(conflict.status, .conflicting)

        XCTAssertEqual(
            GitSourceProvenance(declarations: [
                GitDeclarationEvidence(
                    repository: https,
                    reference: tag,
                    syntaxIsSupported: false
                ),
            ]).status,
            .unsupportedSyntax
        )
        XCTAssertEqual(
            GitSourceProvenance(declarations: [
                GitDeclarationEvidence(repository: credentialed, reference: tag),
            ]).status,
            .credentialBearing
        )
    }

    func testAmbiguousRepositoryDoesNotMaskMalformedOrConflictingLockEvidence() throws {
        let ambiguous = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Repo"
        )
        let different = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Different"
        )
        let branch = try XCTUnwrap(GitReferenceEvidence.make(kind: .branch, value: "main"))
        let declaration = GitDeclarationEvidence(repository: ambiguous, reference: branch)

        XCTAssertEqual(
            GitSourceProvenance(
                declarations: [declaration],
                lockfile: GitLockfileEvidence(hasMalformedEvidence: true)
            ).status,
            .incomplete
        )
        XCTAssertEqual(
            GitSourceProvenance(
                declarations: [declaration],
                lockfile: GitLockfileEvidence(
                    externalSourceRepository: different,
                    externalSourceReference: branch
                )
            ).status,
            .conflicting
        )
    }

    func testDeclarationsAreSortedDeterministicallyAcrossConstructionAndDecoding() throws {
        let firstRepository = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/A/Repo"
        )
        let secondRepository = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/B/Repo"
        )
        let tag = try XCTUnwrap(GitReferenceEvidence.make(kind: .tag, value: "1.0.0"))
        let first = GitDeclarationEvidence(repository: firstRepository, reference: tag)
        let second = GitDeclarationEvidence(repository: secondRepository, reference: tag)

        let lhs = GitSourceProvenance(declarations: [second, first])
        let rhs = GitSourceProvenance(declarations: [first, second])
        XCTAssertEqual(lhs, rhs)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(lhs), try encoder.encode(rhs))
        XCTAssertEqual(try JSONDecoder().decode(GitSourceProvenance.self, from: encoder.encode(lhs)), lhs)
    }

    func testCodableRejectsTamperedDerivedStatus() throws {
        let repository = GitRepositoryCanonicalizer.evidence(for: "https://example.com/A/Repo")
        let branch = try XCTUnwrap(GitReferenceEvidence.make(kind: .branch, value: "main"))
        let provenance = GitSourceProvenance(declarations: [
            GitDeclarationEvidence(repository: repository, reference: branch),
        ])
        let data = try JSONEncoder().encode(provenance)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["status"] = GitSourceEvidenceStatus.supportedImmutable.rawValue
        let tampered = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(GitSourceProvenance.self, from: tampered))
    }

    func testCodableRejectsTamperedReferenceStabilityAndCanonicalIdentity() throws {
        let branch = try XCTUnwrap(GitReferenceEvidence.make(kind: .branch, value: "main"))
        var referenceObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(branch)) as? [String: Any]
        )
        referenceObject["declaredStability"] = GitReferenceStability.declaredImmutable.rawValue
        let tamperedReference = try JSONSerialization.data(withJSONObject: referenceObject)
        XCTAssertThrowsError(
            try JSONDecoder().decode(GitReferenceEvidence.self, from: tamperedReference)
        )

        let identityData = Data(#"{"value":"https://user:pass@example.com/A/Repo"}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(CanonicalRepositoryIdentity.self, from: identityData)
        )

        let repository = GitRepositoryCanonicalizer.evidence(for: "https://example.com/A/Repo")
        var repositoryObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(repository)) as? [String: Any]
        )
        repositoryObject["status"] = GitRepositoryEvidenceStatus.ambiguousRepository.rawValue
        let tamperedRepository = try JSONSerialization.data(withJSONObject: repositoryObject)
        XCTAssertThrowsError(
            try JSONDecoder().decode(GitRepositoryEvidence.self, from: tamperedRepository)
        )
    }

    func testUnsupportedSyntaxMarkerWinsOverItsRedactedRepositoryMarker() {
        XCTAssertEqual(GitSourceProvenance.unsupportedSyntax.status, .unsupportedSyntax)
    }

    func testDependencySourceWrapperAndContainingModelsRoundTrip() throws {
        let repository = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Owner/Repo.git"
        )
        let branch = try XCTUnwrap(GitReferenceEvidence.make(kind: .branch, value: "main"))
        let wrapped = DependencySourceProvenance.git(GitSourceProvenance(declarations: [
            GitDeclarationEvidence(repository: repository, reference: branch),
        ]))
        let dependency = CocoaPodDependency(
            name: "ExternalKit",
            version: "1.0.0",
            source: .git(url: repository.displayURL, ref: .branch("main")),
            sourceProvenance: wrapped,
            isDirect: true
        )
        let entry = MigrationPlanEntry(
            podName: dependency.name,
            currentVersion: dependency.version,
            sourceProvenance: wrapped,
            classification: .review,
            actions: [.manual(description: "Review external source")]
        )

        let decoder = JSONDecoder()
        XCTAssertEqual(
            try decoder.decode(CocoaPodDependency.self, from: JSONEncoder().encode(dependency)),
            dependency
        )
        let decodedEntry = try decoder.decode(
            MigrationPlanEntry.self,
            from: JSONEncoder().encode(entry)
        )
        XCTAssertEqual(decodedEntry.sourceProvenance, wrapped)

        let unknownKind = Data(#"{"kind":"path","git":{}}"#.utf8)
        XCTAssertThrowsError(
            try decoder.decode(DependencySourceProvenance.self, from: unknownKind)
        )
    }

    func testExplicitMalformedAndConflictingLockEvidenceFailClosed() {
        let repository = GitRepositoryCanonicalizer.evidence(
            for: "https://example.com/Owner/Repo.git"
        )
        let declaration = GitDeclarationEvidence(
            repository: repository,
            reference: .unpinned
        )

        XCTAssertEqual(
            GitSourceProvenance(
                declarations: [declaration],
                lockfile: GitLockfileEvidence(hasConflictingEvidence: true)
            ).status,
            .conflicting
        )
        XCTAssertEqual(
            GitSourceProvenance(
                declarations: [declaration],
                lockfile: GitLockfileEvidence(hasMalformedEvidence: true)
            ).status,
            .incomplete
        )
    }

}

import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App


func testEditSession(for volume: VolumeViewModel) -> EditSession {
  EditSession(
    recordId: volume.id,
    fields: [
    "title": .string(volume.title), "description": .string(volume.description),
    "notes": .string(volume.notes),
    ],
    stagedCoverAssetId: nil, sampleAssetIds: nil, createdAt: Date(), updatedAt: Date())
}

func testVersion(
  version: Int, state: String, submittedBy: String = "auth0|submitter",
  reviewedBy: String? = nil, reviewNote: String? = nil
) -> VolumeVersionAttributes {
  VolumeVersionAttributes(
    id: "ver-\(version)", recordId: "1", version: version, title: "Rusthaven",
    description: "", notes: "", format: "", coverAssetId: "", sampleAssetIds: [], state: state,
    baseVersion: version > 1 ? version - 1 : nil, submittedBy: submittedBy,
    submittedAt: Date(timeIntervalSince1970: 0), reviewedBy: reviewedBy, reviewedAt: nil,
    reviewNote: reviewNote, resultingVersion: nil)
}

import AdminAPIClient
import CatalogAPIClient
import Foundation
import Redis
import Testing
import VaporTesting

@testable import App

@Suite("Sort")
struct SortTests {
  @Test("sortByName orders ascending, descending, and case-insensitively")
  func sortByNameOrdersAscendingDescendingAndCaseInsensitively() {
    let names = ["wizards", "Adventurer's", "monte cook"]
    #expect(sortByName(names, order: .asc) { $0 } == ["Adventurer's", "monte cook", "wizards"])
    #expect(sortByName(names, order: .desc) { $0 } == ["wizards", "monte cook", "Adventurer's"])
  }

  @Test("resolveBrowseSortOrder falls back to ascending for missing or unrecognized input")
  func resolveBrowseSortOrderFallsBackToAscending() {
    #expect(resolveBrowseSortOrder(nil) == .asc)
    #expect(resolveBrowseSortOrder("") == .asc)
    #expect(resolveBrowseSortOrder("sideways") == .asc)
    #expect(resolveBrowseSortOrder("desc") == .desc)
  }

}

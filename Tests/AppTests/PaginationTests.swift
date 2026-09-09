import Testing

@testable import App

@Suite("Pagination")
struct PaginationTests {
  @Test("total pages derive from the server count, not the current page's item count")
  func totalPagesFromServerCount() {
    // 95 matches at 30/page -> 4 pages, even though this page only carries a partial slice.
    let p = makePagination(
      totalCount: 95, page: 1, basePath: "", path: "/publishers", query: [:])
    #expect(p.totalPages == 4)
    #expect(p.hasMultiplePages)
    #expect(p.hasNext)
    #expect(!p.hasPrev)
  }

  @Test("an out-of-range page clamps to the last real page")
  func outOfRangePageClamps() {
    let p = makePagination(
      totalCount: 45, page: 9, basePath: "", path: "/studios", query: [:])
    #expect(p.totalPages == 2)
    #expect(p.currentPage == 2)
    #expect(!p.hasNext)
    #expect(p.hasPrev)
  }

  @Test("zero matches still yields one page and no prev/next")
  func zeroMatchesOnePage() {
    let p = makePagination(
      totalCount: 0, page: 1, basePath: "", path: "/persons", query: [:])
    #expect(p.totalPages == 1)
    #expect(!p.hasMultiplePages)
    #expect(!p.hasNext)
    #expect(!p.hasPrev)
  }

  @Test("page links carry the base path, search query, and encoded page number")
  func pageLinksCarryContext() {
    let p = makePagination(
      totalCount: 100, page: 2, basePath: "/catalog", path: "/licenses",
      query: ["q": "monte cook", "order": "desc"])
    let third = p.pages.first { $0.number == 3 }
    #expect(third?.url == "/catalog/licenses?order=desc&page=3&q=monte%20cook")
    // page 1 link omits the redundant page param
    #expect(p.pages.first { $0.number == 1 }?.url == "/catalog/licenses?order=desc&q=monte%20cook")
  }

  @Test("the page-number window spans at most two either side of the current page")
  func windowIsBounded() {
    let p = makePagination(
      totalCount: 300, page: 6, basePath: "", path: "/publishers", query: [:])
    #expect(p.pages.map(\.number) == [4, 5, 6, 7, 8])
  }

  @Test("pageStartOffset maps a 1-based page to its page[start] offset")
  func startOffset() {
    #expect(pageStartOffset(1) == 0)
    #expect(pageStartOffset(3) == 60)
    #expect(pageStartOffset(0) == 0)
  }
}

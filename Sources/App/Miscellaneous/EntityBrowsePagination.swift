import Vapor

/// Page-link data for a browse page's pagination footer - a small window of page numbers
/// around the current page, plus prev/next, each with a ready-built URL (query string already
/// encoded) so the Leaf template only has to render hrefs, not construct them.
struct LeafPageLink: Content {
  let number: Int
  let url: String
  let isCurrent: Bool
}

struct LeafPagination: Content {
  let currentPage: Int
  let totalPages: Int
  let hasMultiplePages: Bool
  let hasPrev: Bool
  let hasNext: Bool
  let prevURL: String
  let nextURL: String
  let pages: [LeafPageLink]
}

/// How many cards a browse page shows per page - small enough that a page loads fast, large
/// enough that browsing a few hundred records doesn't take many clicks.
let browsePageSize = 30

/// The `page[start]` offset a 1-based browse page number maps to, for the catalog-api query.
func pageStartOffset(_ requestedPage: Int) -> Int {
  max(0, requestedPage - 1) * browsePageSize
}

/// Builds a browse page's pagination footer from a server-reported total match count rather than
/// from a client-side slice - the page's items were already narrowed to one `page[limit]` window
/// by catalog-api, so paging math runs off `totalCount` (its `meta.total`), not `items.count`.
/// Out-of-range page numbers still clamp to the last real page rather than erroring - a stale
/// bookmarked `?page=9` after the list shrank falls back to the last page, not 404.
func makePagination(
  totalCount: Int, page requestedPage: Int, basePath: String, path: String,
  query: [String: String]
) -> LeafPagination {
  let totalPages = max(1, Int((Double(totalCount) / Double(browsePageSize)).rounded(.up)))
  let page = min(max(1, requestedPage), totalPages)

  func url(for pageNumber: Int) -> String {
    var params = query.filter { !$0.value.isEmpty }
    if pageNumber > 1 {
      params["page"] = String(pageNumber)
    }
    guard !params.isEmpty else { return "\(basePath)\(path)" }
    let queryString = params.sorted { $0.key < $1.key }
      .map { key, value in
        let encoded =
          value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        return "\(key)=\(encoded)"
      }
      .joined(separator: "&")
    return "\(basePath)\(path)?\(queryString)"
  }

  // A window of up to 5 page numbers centered on the current page, clamped to stay in range -
  // avoids listing hundreds of page links for a large collection.
  let windowRadius = 2
  let windowStart = max(1, page - windowRadius)
  let windowEnd = min(totalPages, page + windowRadius)
  let pages = (windowStart...windowEnd).map { number in
    LeafPageLink(number: number, url: url(for: number), isCurrent: number == page)
  }

  return LeafPagination(
    currentPage: page,
    totalPages: totalPages,
    hasMultiplePages: totalPages > 1,
    hasPrev: page > 1,
    hasNext: page < totalPages,
    prevURL: url(for: page - 1),
    nextURL: url(for: page + 1),
    pages: pages
  )
}

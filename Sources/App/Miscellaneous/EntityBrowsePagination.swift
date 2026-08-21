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

/// Slices `items` (already filtered/sorted) to the requested page, clamping out-of-range page
/// numbers rather than erroring - a stale bookmarked `?page=9` after the underlying list shrank
/// should fall back to the last real page, not 404 or show nothing.
func paginate<T>(
  _ items: [T], page requestedPage: Int, basePath: String, path: String,
  query: [String: String]
) -> (slice: [T], pagination: LeafPagination) {
  let totalPages = max(1, Int((Double(items.count) / Double(browsePageSize)).rounded(.up)))
  let page = min(max(1, requestedPage), totalPages)
  let start = (page - 1) * browsePageSize
  let end = min(start + browsePageSize, items.count)
  let slice = start < end ? Array(items[start..<end]) : []

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

  return (
    slice,
    LeafPagination(
      currentPage: page,
      totalPages: totalPages,
      hasMultiplePages: totalPages > 1,
      hasPrev: page > 1,
      hasNext: page < totalPages,
      prevURL: url(for: page - 1),
      nextURL: url(for: page + 1),
      pages: pages
    )
  )
}

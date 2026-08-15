import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafReview: Content {
  let author: String
  let starsLabel: String
  let text: String

  init(_ review: (author: String, rating: Int, text: String)) {
    self.author = review.author
    self.starsLabel =
      String(repeating: "\u{2605}", count: max(0, min(5, review.rating)))
      + String(repeating: "\u{2606}", count: max(0, 5 - review.rating))
    self.text = review.text
  }
}

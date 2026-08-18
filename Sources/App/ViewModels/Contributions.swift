import CatalogAPIClient
import Crypto
import Foundation
import Vapor

struct LeafCredit: Content {
  let role: String
  let person: String

  init(_ credit: (personId: String, role: String, person: String)) {
    self.role = credit.role
    self.person = credit.person
  }
}

/// One selected contributor credit - a person plus the contribution type they're credited for.
struct LeafSelectedCredit: Content {
  let personId: String
  let personName: String
  let contributionType: String
}

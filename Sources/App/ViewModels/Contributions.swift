import CatalogAPIClient
import Crypto
import Foundation
import Vapor

/// One credited person on a volume, with every contribution type they hold for that volume
/// collapsed into a single comma-separated `rolesLabel`. Built by `groupCreditsByPerson` so the
/// detail template renders one line per person instead of one line per (person, role) pair.
struct LeafCreditGroup: Content {
  let personId: String
  let person: String
  let rolesLabel: String
}

/// Groups a flat `[(personId, role, person)]` credit list by person, keeping first-seen order for
/// both persons and each person's roles, and joins the roles with ", " into `rolesLabel`. The
/// API already returns credits in display order, so nothing is re-sorted.
func groupCreditsByPerson(
  _ credits: [(personId: String, role: String, person: String)]
) -> [LeafCreditGroup] {
  var order: [String] = []
  var rolesByPerson: [String: [String]] = [:]
  var nameByPerson: [String: String] = [:]
  for credit in credits {
    if rolesByPerson[credit.personId] == nil {
      order.append(credit.personId)
      rolesByPerson[credit.personId] = []
      nameByPerson[credit.personId] = credit.person
    }
    if !rolesByPerson[credit.personId]!.contains(credit.role) {
      rolesByPerson[credit.personId]!.append(credit.role)
    }
  }
  return order.map { id in
    LeafCreditGroup(
      personId: id, person: nameByPerson[id] ?? "",
      rolesLabel: rolesByPerson[id]!.joined(separator: ", "))
  }
}

/// One selected contributor credit - a person plus the contribution type they're credited for.
struct LeafSelectedCredit: Content {
  let personId: String
  let personName: String
  let contributionType: String
}

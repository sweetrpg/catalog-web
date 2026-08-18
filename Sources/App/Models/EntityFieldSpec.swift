/// How a field's edit control should render - most fields are a single-line text input, but a
/// few need a textarea (long-form text) or a closed set of choices (select).
enum EntityFieldKind {
  case text
  case textarea
  case select(options: [String])
}

/// One patchable field's key (matches catalog-api's PATCH field name), display label, and
/// control kind - mirrors CatalogController.swift's private `patchableFields` array, but
/// declared per entity type below instead of hardcoded to volume's three fields.
struct EntityFieldSpec {
  let key: String
  let label: String
  var kind: EntityFieldKind = .text
}

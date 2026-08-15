
/// One patchable field's key (matches catalog-api's PATCH field name) and display label -
/// mirrors CatalogController.swift's private `patchableFields` array, but declared per entity
/// type below instead of hardcoded to volume's three fields.
struct EntityFieldSpec {
  let key: String
  let label: String
}

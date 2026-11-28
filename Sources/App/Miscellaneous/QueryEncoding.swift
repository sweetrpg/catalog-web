import Foundation

/// RFC 3986 unreserved characters. `.urlQueryAllowed` leaves `&`, `+` and `=` as they are, which
/// changes a value's meaning inside a query string.
private let unreserved = CharacterSet(
  charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

func encodeQueryValue(_ value: String) -> String {
  value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
}

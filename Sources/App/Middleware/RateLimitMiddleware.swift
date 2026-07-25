import Vapor

/// Process-wide token bucket rate limiter, mirroring catalog-api's `golang.org/x/time/rate`
/// middleware (docs/service-conventions.md's Rate limiting section): one shared bucket across
/// every route and every client, refilling one token/second up to a `RATE_LIMIT` burst size -
/// not per-client/per-IP. A blunt backstop, not real per-client throttling.
actor TokenBucket {
  private var tokens: Double
  private let capacity: Double
  private var lastRefill: Date

  init(capacity: Int) {
    self.capacity = Double(capacity)
    self.tokens = Double(capacity)
    self.lastRefill = Date()
  }

  func tryConsume() -> Bool {
    let now = Date()
    let elapsed = now.timeIntervalSince(lastRefill)
    tokens = min(capacity, tokens + elapsed)
    lastRefill = now

    guard tokens >= 1 else { return false }
    tokens -= 1
    return true
  }
}

struct RateLimitMiddleware: AsyncMiddleware {
  let bucket: TokenBucket

  init(capacity: Int) {
    self.bucket = TokenBucket(capacity: capacity)
  }

  func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
    guard await bucket.tryConsume() else {
      request.logger.warning("Rate limit exceeded for \(request.method) \(request.url.path)")
      let response = Response(status: .tooManyRequests)
      try response.content.encode(["error": "rate_limited", "message": "Limit exceeded"])
      return response
    }
    return try await next.respond(to: request)
  }
}

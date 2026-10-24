---
name: rest-api-review
description: Review REST (or REST-ish) API designs for resource modelling, HTTP semantics, versioning, error responses, security, and developer ergonomics. Produces a scored report with concrete fixes.
---

Review the provided API specification (OpenAPI YAML/JSON, route list, or prose) and evaluate it across these dimensions:

## 1. Resource modelling (25 pts)
- Resources are nouns, not verbs (`/orders` not `/getOrders`).
- Proper hierarchy without over-nesting (max 2–3 levels deep).
- Collections vs singletons clearly distinguished.
- Actions that don't map cleanly to CRUD use sub-resources or POST with clear semantics (`/orders/{id}/cancel`).

## 2. HTTP semantics (20 pts)
- Correct method usage (GET=safe+idempotent, PUT=idempotent replace, PATCH=partial update, DELETE=idempotent).
- Status codes are precise (201 Created, 204 No Content, 409 Conflict, 422 Unprocessable Entity — not just 200/400/500).
- GET requests have no body. POST to collections, PUT to singletons.
- Idempotency keys for non-idempotent operations (payments, sends).

## 3. Versioning (10 pts)
- Strategy is explicit (URI path `/v1/`, header, or content negotiation).
- Deprecation path is defined.

## 4. Request / response shapes (20 pts)
- Consistent envelope vs. flat response (pick one, don't mix).
- Pagination: cursor-based preferred over offset for large collections.
- Filtering, sorting, field selection via query params follow a consistent pattern.
- Input validation errors include field-level detail, not just a top-level message.

## 5. Error responses (10 pts)
- RFC 9457 (Problem Details) or equivalent consistent structure.
- Machine-readable `type` / `code` field alongside human `detail`.
- No stack traces or internal paths leaked in production errors.

## 6. Security (15 pts)
- Auth scheme is stated and applied consistently.
- Endpoints that mutate state require auth.
- Mass-assignment / over-posting risk (is the response schema the same as the input schema?).
- Rate limiting is mentioned.
- CORS policy is appropriate.

Score each dimension, total out of 100. List top-5 issues by severity with a concrete fix for each. If an OpenAPI file is provided, output a corrected snippet.

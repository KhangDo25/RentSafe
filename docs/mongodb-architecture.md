# RentSafe MongoDB architecture

## Scope and principles

RentSafe is a modular monolith: one Spring Boot application, one React application, and one MongoDB deployment per customer installation. An installation is a hard operational boundary, not a multi-tenant shared database. All collections below belong to that one installation.

The design uses Spring Data MongoDB. It does not use JPA, Hibernate, PostgreSQL, JDBC, or Flyway. Module APIs own their data and other modules depend on those APIs or published domain events, never on another module's repositories or collection internals.

Document identifiers are MongoDB `ObjectId` values unless an immutable public identifier is explicitly required. External-facing identifiers (for example, booking number) are opaque, generated values and are not database IDs. Store money as `{ amount: Decimal128, currency: "ISO-4217" }`, timestamps as UTC BSON dates, and retain the installation's time zone in settings for display and business-day calculations.

## Module boundaries

| Module | Responsibilities | May depend on | Must not own |
| --- | --- | --- | --- |
| `common` | IDs, clock, errors, pagination, money, validation, event/outbox contracts | none | business records or persistence shared by every module |
| `identity` | users, sessions/tokens, roles, password credentials, authorization decisions | common, audit | customer profiles, payments, rental state |
| `customers` | renter organizations/people, contacts, addresses, eligibility flags | common, audit | authentication credentials or invoices |
| `assets` | asset catalog, category definitions, units, availability projection, status transitions | common, settings, audit | booking/rental ownership or payment records |
| `bookings` | quotes, booking requests, confirmed allocations, availability holds | common, customers, assets, audit | checked-out rental execution or payment processing |
| `rentals` | contract created from a confirmed booking, active rental state, extensions | common, customers, assets, bookings, audit | payment capture or physical inspection details |
| `payments` | deposits, charges, refunds, provider reconciliation, immutable financial ledger | common, customers, rentals, audit | provider credentials in business records |
| `handovers` | checkout inspection, signatures, issued items and condition evidence | common, rentals, assets, audit | return finalization |
| `returns` | return inspection, damage/loss assessment, returned quantities | common, rentals, assets, payments, maintenance, audit | maintenance execution |
| `maintenance` | work orders, service history, quarantine/unavailable status requests | common, assets, audit | booking/rental contract changes |
| `reporting` | read models and scheduled aggregations derived from module events | read-only module APIs/events, common | authoritative transactional state |
| `audit` | append-only actor/action records, retention/export controls | common | authorization decisions or mutable business state |
| `settings` | installation profile, currency/time-zone policy, numbering, category policy, payment-provider configuration references | common, audit | passwords, raw provider secrets |

Dependencies flow toward `common`; no module reads another module's Mongo collection directly. Cross-module changes are coordinated by an application service using explicit module commands and, where required, one transaction. Domain events are written to the outbox in the same transaction as their authoritative state; reporting consumes these idempotently.

## Collections and data model

### Core collections

| Collection | Purpose, key fields, and relationships | Indexes and principal queries | Lifecycle |
| --- | --- | --- | --- |
| `users` | Identity account: `emailNormalized`, display name, `passwordHash`, roles, enabled state, MFA metadata, `lastLoginAt`. References no customer record by default; an employee may optionally reference a customer contact. Embed small role assignments and MFA state. | Unique `{ emailNormalized: 1 }`; `{ enabled: 1 }`. Login by email; administrator user search. | Retain while audit history requires it; disable instead of deleting. |
| `customerProfiles` | Individual or organization renter: name, contacts, addresses, document references, credit/eligibility flags, tags, notes. Embed bounded contacts and addresses; store uploaded files in object storage and reference them. | `{ normalizedName: 1 }`, text/search index appropriate to deployment, `{ status: 1, normalizedName: 1 }`. Search and retrieve customer for booking/rental. | Soft archive; restrict deletion when referenced. |
| `assetCategories` | Administrator-defined category schema: name, `attributeDefinitions`, required fields, allowed values, units, and version. This makes cameras, stages, excavators, tools, and vehicles configurable without shared-model special cases. | Unique `{ code: 1 }`; `{ active: 1, name: 1 }`. Fetch schema when editing assets. | Version definitions; deactivate, do not silently invalidate existing assets. |
| `assets` | Rentable unit or serialized asset: `assetCode`, name, category reference/version, `metadata`, ownership/location, condition, status, replacement value, images/document references. `metadata` contains only category-defined values. Embed small bounded tags and status history summary; reference category and external files. | Unique `{ assetCode: 1 }`; `{ categoryId: 1, status: 1 }`; `{ locationId: 1, status: 1 }`; `{ "metadata.<approved searchable key>": 1 }` only for declared searchable attributes. Query catalog/filtering and asset-by-code. | Archive rather than delete after history exists. |
| `availabilityLocks` | Authoritative per-asset, per-date-bucket allocation records for confirmed bookings and active rentals. Fields: `assetId`, `bucketDate`, `allocationId`, `sourceType`, `sourceId`, `rangeStart`, `rangeEnd`, `state`, `expiresAt` for temporary holds. One document per asset/day (or chosen business availability bucket) makes collisions enforceable. | Unique `{ assetId: 1, bucketDate: 1 }`; `{ sourceType: 1, sourceId: 1 }`; TTL `{ expiresAt: 1 }` only for unconfirmed holds. Availability query by asset/range and allocation cleanup. | Delete expired temporary holds with TTL; remove completed allocations only after retention policy. |
| `bookings` | Booking request/quote/confirmed allocation: number, customer reference/snapshot, requested range, lines (`assetId` or category requirement, quantity, price snapshot), state, hold expiry, terms snapshot. Embed booking lines and price/customer display snapshots; reference source assets and customer. | Unique `{ bookingNumber: 1 }`; `{ customerId: 1, startAt: 1 }`; `{ state: 1, startAt: 1 }`; `{ "lines.assetId": 1, startAt: 1, endAt: 1 }`. Calendar, customer history, pickup queue. | Immutable confirmation/audit history; cancel rather than delete. |
| `rentals` | Executable rental contract: number, booking reference, customer and pricing snapshots, allocated asset lines, start/end, state, extension history, deposit summary. Embed contract/line snapshots because they are legal and operational history; reference booking, customer, assets, and payments. | Unique `{ rentalNumber: 1 }`; `{ state: 1, plannedStartAt: 1 }`; `{ customerId: 1, plannedEndAt: 1 }`; `{ "lines.assetId": 1, state: 1 }`. Pickup/overdue queues and customer history. | Never overwrite contract facts; preserve snapshots, close/cancel states, archive by retention policy. |
| `payments` | Immutable financial events: rental/customer reference, type (`deposit`, charge, refund, adjustment), money, status, provider reference, idempotency key, authorization/capture timestamps. Do not embed provider secrets or full card data. | Unique sparse `{ provider: 1, providerTransactionId: 1 }`; unique `{ idempotencyKey: 1 }`; `{ rentalId: 1, createdAt: -1 }`; `{ status: 1, createdAt: 1 }`. Reconciliation and rental balance. | Append adjustments/refunds rather than mutate settled records; retention per finance rules. |
| `handovers` | Checkout event linked one-to-one or one-to-many to rental: issued asset lines, condition checklist, meter readings, photos/signature references, operator, timestamp. Embed bounded checklists/readings; object-store large media. | `{ rentalId: 1, completedAt: -1 }`; `{ "lines.assetId": 1, completedAt: -1 }`. Pickup verification and asset history. | Immutable completed inspection record. |
| `returns` | Return event and inspection: received asset lines, condition comparison, meter readings, damage/loss items, media/signature references, assessed charges, state. References rental, assets, and resulting payment/maintenance records. | `{ rentalId: 1, completedAt: -1 }`; `{ "lines.assetId": 1, completedAt: -1 }`; `{ state: 1, completedAt: 1 }`. Return desk and unassessed damage queues. | Immutable completed inspection; corrections become linked amendments. |
| `maintenanceWorkOrders` | Maintenance/repair/inspection task: asset reference, reason, priority, workflow state, scheduled/completed dates, vendor/cost snapshots, findings. | `{ assetId: 1, state: 1 }`; `{ state: 1, scheduledAt: 1 }`; `{ priority: 1, state: 1 }`. Workshop queue and asset maintenance history. | Retain completed history; archive closed work orders. |
| `auditEvents` | Append-only security and business audit record: timestamp, actor, action, target type/id, request/correlation ID, before/after hashes or redacted summaries, IP/user-agent where lawful. | `{ occurredAt: -1 }`; `{ targetType: 1, targetId: 1, occurredAt: -1 }`; `{ actorId: 1, occurredAt: -1 }`. Investigations and exports. | Immutable; retention and legal-hold policy in settings. |
| `outboxEvents` | Transactional integration/event delivery record: event ID/type/version, aggregate reference, payload, occurred time, delivery state and attempts. | Unique `{ eventId: 1 }`; `{ deliveryState: 1, occurredAt: 1 }`. Reporting projection and reliable post-commit work. | Purge only after delivery plus retention window. |
| `reportingSnapshots` | Small materialized read models and aggregate snapshots, keyed by report name/period/filter version. It is optional and never the source of truth. | Unique `{ reportKey: 1, period: 1, dimensionsHash: 1 }`; `{ generatedAt: -1 }`. Dashboard/report reads. | Rebuildable; expire/rebuild according to reporting policy. |
| `settings` | One installation document (or a small set by scope): company profile, time zone, currency/tax defaults, numbering counters/policy, retention, category and security policies, secret *references*. | Unique `{ scope: 1 }`. Load configuration and allocation counters. | Versioned updates; audited. |

Do not create separate collections for tags, locations, conditions, contacts, booking lines, rental lines, or inspection checklists unless their size, independent lifecycle, or query volume proves it necessary. Embed bounded data read and updated with its parent. Reference entities with independent ownership, large fan-out, independent security, or unbounded growth. Store binary evidence outside MongoDB unless GridFS is deliberately adopted; retain immutable object references and checksums in inspection documents.

### Asset metadata and industry flexibility

Every asset has stable shared fields such as identity, status, location, category, condition, ownership, and replacement value. Industry-specific values live in `assets.metadata`, validated against the immutable category schema version recorded on the asset.

An `assetCategories.attributeDefinitions` entry contains an attribute key, display label, data type, unit, required flag, validation constraints, select options, and flags for filtering/sorting. Example categories may define lens mount and sensor format, stage load rating, excavation bucket capacity, or vehicle odometer; none of those fields exist in the shared asset schema. Only attributes declared searchable receive controlled Mongo indexes. This prevents unbounded dynamic-index growth and keeps the data model universal.

## Consistency and transaction strategy

### Booking overlap and concurrent requests

Availability is enforced by `availabilityLocks`, not by a read-then-write calendar check. For each serialized asset and each date bucket in the requested interval, confirmation inserts/claims a lock document protected by the unique `{ assetId, bucketDate }` index. A request succeeds only when it owns every required lock. A duplicate-key error means the asset is unavailable for at least one bucket; report a conflict after re-checking availability.

The confirmation transaction creates/updates the booking, writes every lock, writes an audit event and outbox event. For multi-quantity category requests, the allocation service first selects concrete eligible assets in a deterministic order, then locks them in the same transaction. Temporary holds carry `expiresAt`; confirmation replaces their state atomically before expiry. Requests use idempotency keys so retries cannot create duplicate bookings.

### Asset status transitions

Asset status is a finite state machine (for example `available`, `reserved`, `checked_out`, `inspection`, `maintenance`, `retired`). Simple transitions that change one asset and record its bounded history use an atomic `findOneAndUpdate` with predicates for the expected current state and a version field. If a transition also changes rental/booking records, locks, or an outbox event, use a transaction.

### Extensions, payments, and return inspections

- **Rental extension:** re-lock the additional availability buckets and conditionally update the rental's end time/version in one transaction. If any lock conflicts, reject or offer only the available extension period.
- **Deposits and payments:** persist payment attempts and provider callbacks with an idempotency key. A provider callback changes one payment record atomically; a transaction is needed only when it also changes rental eligibility/deposit summary and creates audit/outbox records. Never treat a client redirect as settlement confirmation.
- **Return inspection:** create the immutable return document, transition the rental/line states, update each affected asset to `available`, `inspection`, or `maintenance`, create work orders where needed, and write audit/outbox records in one transaction. Media upload is outside the transaction; store it first as pending and attach only successfully finalized immutable object references.

### Atomic operations, transactions, and rollback

Use atomic single-document updates for status changes, one payment callback, allocation-counter increments, and optimistic version checks. Use multi-document MongoDB transactions for booking confirmation/cancellation, rental checkout, rental extension, return finalization, deposit state changes coupled to rental eligibility, and any operation that must update multiple authoritative collections together.

Transactions are short, retried only when safe, and executed against a replica set (including self-hosted single-node replica-set development deployments where transactions are needed). External effects—email, payment capture, object uploads—are never rolled back by MongoDB. Commit the state plus an outbox event; workers execute external effects idempotently afterward. On transaction failure, MongoDB rolls back its writes; the service returns no success until commit succeeds. Compensating records, not destructive edits, correct completed financial or inspection events.

## Self-hosted isolation and operations

- Each customer runs a separate RentSafe installation with its own MongoDB deployment/database, credentials, encryption keys, backups, and operational administrator. No shared multi-customer collection and no cross-installation query exists.
- MongoDB is reachable only on the internal Docker network by the backend. The default Compose design must omit MongoDB `ports:` entirely. Development-only local exposure, if required, belongs in an explicit override file bound to loopback.
- The frontend communicates only with the backend API. It never receives MongoDB credentials, a database connection URI, or privileged provider credentials.
- Run MongoDB with persistent volumes, a non-root application database user with only required roles, authenticated connections, and a replica-set topology appropriate for transaction and recovery requirements.
- Back up each installation independently with encrypted, access-controlled, tested point-in-time or scheduled backups. Preserve Mongo metadata, indexes, and object-store evidence. Restore tests must target an isolated replacement environment and document recovery objectives.

## Security baseline

- Authenticate users through the `identity` module; store passwords only as tuned Argon2id hashes (with a per-password salt). Support secure reset flows, MFA for privileged roles, session revocation, rate limiting, and account lockout policies.
- Enforce server-side role/permission checks on every API operation; frontend controls are not authorization. Use least-privilege roles and explicitly protect financial, customer-document, settings, export, and audit actions.
- Keep database passwords, token signing keys, payment-provider credentials, and backup encryption keys in deployment secret storage or protected environment injection. Do not commit secrets, return them from APIs, or store raw values in `settings`.
- Require TLS at the public reverse proxy and TLS/authentication for MongoDB connections where the deployment topology crosses host boundaries. Restrict firewall and Docker networks; no public MongoDB listener by default.
- Encrypt backup archives and sensitive uploaded evidence; use access control and retention policies for personal data. Minimize logged personal/payment data and redact secrets from application logs.
- Write append-only audit events for authentication, authorization failures, settings changes, financial events, booking/rental state changes, exports, and destructive administrative actions. Protect audit access and retention separately from operational logs.
- Apply supported MongoDB and container image patching, backup restore drills, dependency scanning, security headers, CORS allowlists, CSRF protection for cookie-based sessions, and request-size/rate limits.

## Unresolved design questions

1. Is an asset always individually serialized, or must some categories support interchangeable stock quantities? The initial lock model assumes serialized units; pooled inventory needs a bounded per-bucket counter design.
2. Which payment providers, currencies, tax jurisdictions, and deposit rules are required in the first release?
3. What are the legal retention, privacy, audit-export, and backup recovery objectives for each customer market?
4. Must offline handover/return workflows be supported? If so, conflict-resolution rules and local synchronization must be designed explicitly.
5. What are the required reporting scale, search capabilities, and acceptable reporting lag? Those answers determine whether Mongo text search, Atlas Search-compatible services, or an external search/reporting component is appropriate.

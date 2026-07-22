# Chronicle Elixir Console Sample

An interactive employee-focused console sample that mirrors the Chronicle TypeScript console sample.

## What it demonstrates

- Seeding Ada Lovelace, Grace Hopper, and Alan Turing through `EmployeeSeeder`
- Employee lifecycle events: `EmployeeHired`, `EmployeePromoted`, `EmployeeMoved`, `EmployeeEmailSet`, and `EmployeeAddressSet`
- Reducer-backed `EmployeeState` read models
- Reacts to those events via `HrNotificationReactor` (console notifications)
- Model-bound constraints for unique employee hire and case-insensitive unique email addresses
- Transactional multi-employee updates through `Chronicle.Transactions.UnitOfWork`
- A customer compliance / PII walkthrough with register-and-view commands

## Controls

- `1`-`3` — select Ada, Grace, or Alan
- `P` — promote the selected employee
- `A` — move the selected employee to a new address
- `E` — set the selected employee's canonical email address
- `U` — try to steal the next employee's email (constraint violation)
- `R` — read the selected employee's `EmployeeState` read model
- `T` — commit a transactional multi-employee update
- `C` — register a customer with PII-style data
- `V` — view the customer read model
- `H` / `?` — show help
- `Q` — quit

## Prerequisites

- Elixir 1.14+ and OTP 25+
- A Chronicle kernel running on `localhost:35000`

## Running

```shell
cd Samples/console
docker compose up -d
mix deps.get
mix run --no-halt
```

By default the sample connects with Chronicle's built-in development credentials:

```text
chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000
```

The Chronicle kernel requires authentication, so the client credentials are needed
for the gRPC calls to succeed — the client exchanges them for a bearer token against
the kernel's `/connect/token` endpoint, served on the same port (`35000`) as the
gRPC channel.

Override the Chronicle connection string with:

```shell
CHRONICLE_CONNECTION_STRING="chronicle://client-id:client-secret@myserver:35000" mix run --no-halt
```

## Notes

The customer commands are a compliance demonstration that routes personally identifiable information through events and reducer-backed read models. The Elixir sample labels those fields clearly in the console output so you can see which fields require protection in downstream systems.

### PII encryption

The customer event types and read model mark their sensitive fields with the
`pii/1,2` macro (for example `pii :email, "Customer email address"`). The
Chronicle Elixir client embeds that marking as `compliance` metadata in the
generated JSON schema, and the kernel encrypts those values at rest.

Two things are required for encryption to actually happen:

- **A subject must be supplied on append** — the kernel derives the per-subject
  encryption key from it. The sample passes `subject: customer_id` when
  registering the customer. Without a subject the kernel skips compliance.
- **The event type must carry the PII metadata at first registration** — the
  kernel does not allow changing a registered event type's schema at the same
  generation (`EventTypeSchemaChanged`). If you have already run the sample
  against a store before the PII markings were added, start from a clean store
  (drop the MongoDB volumes, or use a fresh event store name) so the types
  register with the compliance metadata.

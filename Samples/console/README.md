# Chronicle Elixir console sample

An interactive, employee-focused console application built on the Chronicle Elixir client, using the client source in `Source/chronicle`. It mirrors the Chronicle TypeScript console sample.

## What it demonstrates

- Seeding Ada Lovelace, Grace Hopper, and Alan Turing through `EmployeeSeeder`
- Employee lifecycle events: `EmployeeHired`, `EmployeePromoted`, `EmployeeMoved`, `EmployeeEmailSet`, and `EmployeeAddressSet`
- A model-bound projection (`EmployeeDetails`) and a declarative projection (`EmployeeListProjection`)
- Reducer-backed `EmployeeState` and `Customer` read models
- Reacting to events in `HrNotificationReactor`, which prints console notifications
- Model-bound constraints for unique employee hires and case-insensitive unique email addresses
- Transactional multi-employee updates through `Chronicle.Transactions.UnitOfWork`
- Process-scoped identity and causation, with a switchable acting user
- A customer compliance walkthrough with PII-marked fields, redaction, and GDPR erasure
- Registering an external service and renaming an identity

## Prerequisites

- Elixir 1.18 or later (CI uses Elixir 1.19.5 on Erlang/OTP 28.5)
- Docker with Docker Compose

## Running

```shell
cd Samples/console
docker compose pull
docker compose up -d
mix deps.get
mix deps.update cratis_chronicle_contracts
mix run --no-halt
```

`docker compose up -d` starts the Chronicle kernel on `localhost:35000`, MongoDB, and an Aspire dashboard on `http://localhost:18888`, all bound to this machine only.

The `mix deps.update cratis_chronicle_contracts` step matters: the sample's `mix.lock` pins the generated contracts version that was current when the lock was last updated, and the kernel image you just pulled may be newer. Updating it resolves the newest contracts, which match the freshly pulled `latest-development-slim` kernel image. If the kernel and contracts versions don't match, appends return `{:error, {:incompatible_server, ...}}`.

The sample waits up to 30 seconds for the client to finish registering, then prints each seeded employee's status and the controls.

## Credentials

By default the sample connects with Chronicle's built-in development credentials:

```text
chronicle://chronicle-dev-client:chronicle-dev-secret@localhost:35000
```

The development kernel requires an authenticated client. The client exchanges these credentials for a bearer token at the kernel's `/connect/token` endpoint, on the same port as gRPC. They are well known and only for a local development kernel.

To connect to another kernel, set `CHRONICLE_CONNECTION_STRING`:

```shell
CHRONICLE_CONNECTION_STRING="chronicle://client-id:client-secret@myserver:35000?skipTlsValidation=false" mix run --no-halt
```

`skipTlsValidation=false` makes the client validate the server's certificate; without it, any certificate is accepted.

## Controls

Select an employee with `1`, `2` or `3`, then press a key:

| Key | Action |
|-----|--------|
| `1`-`3` | Select Ada, Grace, or Alan |
| `P` | Promote the selected employee |
| `A` | Move the selected employee to a new address |
| `E` | Set the selected employee's canonical email address |
| `U` | Try to take the next employee's email (constraint violation) |
| `R` | Read the selected employee's reducer-backed `EmployeeState` read model |
| `J` | Read the model-bound `EmployeeDetails` projection |
| `K` | Read the declarative `EmployeeList` projection |
| `T` | Commit a transactional multi-employee update |
| `W` | Promote and wait for every observer to process the event |
| `C` | Register a customer with PII-marked data |
| `V` | View the customer read model |
| `X` | Register the `CustomersApi` external service |
| `N` | Rename the acting user's identity |
| `I` | Switch the acting user: Alice Smith, Bob Jones, System |
| `D` | Permanently redact the selected employee's last event |
| `G` | Permanently erase every event for the sample customer |
| `H` / `?` | Show the controls |
| `Q` | Quit |

`D` and `G` can't be undone. To start over, stop the sample and remove the containers and their data with `docker compose down -v`.

## PII encryption

The customer event types mark their sensitive fields with the `pii/2` macro, for example `pii :email, "Customer email address"`. The client embeds that marking as `compliance` metadata in the generated JSON schema, and the kernel encrypts those values at rest.

Two things are required for encryption to happen:

- **A subject must be supplied on append.** The kernel derives the per-subject encryption key from it. The sample passes `subject: customer_id` when registering the customer. Without a subject, the kernel skips compliance.
- **The event type must carry the PII metadata when it is first registered.** The kernel doesn't allow changing a registered event type's schema at the same generation (`EventTypeSchemaChanged`). If you ran the sample against a store before the PII markings were added, start from a clean store with `docker compose down -v`.

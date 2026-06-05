# Chronicle Elixir Console Sample

An interactive employee-focused console sample that mirrors the Chronicle TypeScript console sample.

## What it demonstrates

- Seeding Ada Lovelace, Grace Hopper, and Alan Turing through `EmployeeSeeder`
- Employee lifecycle events: `EmployeeHired`, `EmployeePromoted`, `EmployeeMoved`, `EmployeeEmailSet`, and `EmployeeAddressSet`
- Reducer-backed `EmployeeState` read models
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
mix deps.get
mix run --no-halt
```

Override the Chronicle connection string with:

```shell
CHRONICLE_CONNECTION_STRING="chronicle://myserver:35000?apiKey=secret" mix run --no-halt
```

## Notes

The customer commands are a compliance demonstration that routes personally identifiable information through events and reducer-backed read models. The Elixir sample labels those fields clearly in the console output so you can see which fields require protection in downstream systems.

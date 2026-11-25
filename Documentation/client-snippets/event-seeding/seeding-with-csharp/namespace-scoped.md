```elixir
defmodule MyApp.Events.EvtSeedingNsProductCreated do
  use Cratis.Chronicle.Events.EventType, id: "evt-seeding-ns-product-created"

  defstruct [:name, :price]
end

defmodule MyApp.Events.EvtSeedingNsUserRegistered do
  use Cratis.Chronicle.Events.EventType, id: "evt-seeding-ns-user-registered"

  defstruct [:email, :display_name]
end

defmodule MyApp.Events.EvtSeedingNsOrganizationCreated do
  use Cratis.Chronicle.Events.EventType, id: "evt-seeding-ns-organization-created"

  defstruct [:name]
end

defmodule MyApp.Events.EvtSeedingNsBillingSetUp do
  use Cratis.Chronicle.Events.EventType, id: "evt-seeding-ns-billing-set-up"

  defstruct [:billing_email]
end

defmodule MyApp.Seeders.EvtSeedingTenantSeeding do
  use Cratis.Chronicle.Seeding.Seeder

  alias MyApp.Events.{
    EvtSeedingNsBillingSetUp,
    EvtSeedingNsOrganizationCreated,
    EvtSeedingNsProductCreated,
    EvtSeedingNsUserRegistered
  }

  @impl true
  def seed(builder) do
    builder
    # Global seed data — applied to every namespace
    |> Cratis.Chronicle.Seeding.for(EvtSeedingNsProductCreated, "product-1", [
      %EvtSeedingNsProductCreated{name: "Laptop", price: 1299.00}
    ])
    # Namespace-scoped seed data — applied only to the "acme" namespace
    |> Cratis.Chronicle.Seeding.for_namespace("acme", fn scoped ->
      Cratis.Chronicle.Seeding.for(scoped, EvtSeedingNsUserRegistered, "user-1", [
        %EvtSeedingNsUserRegistered{email: "admin@acme.com", display_name: "Acme Admin"}
      ])
    end)
    # A second namespace with different seed data
    |> Cratis.Chronicle.Seeding.for_namespace("contoso", fn scoped ->
      scoped
      |> Cratis.Chronicle.Seeding.for(EvtSeedingNsUserRegistered, "user-1", [
        %EvtSeedingNsUserRegistered{email: "admin@contoso.com", display_name: "Contoso Admin"}
      ])
      |> Cratis.Chronicle.Seeding.for_event_source("org-1", [
        %EvtSeedingNsOrganizationCreated{name: "Contoso"},
        %EvtSeedingNsBillingSetUp{billing_email: "contoso@billing.com"}
      ])
    end)
  end
end
```

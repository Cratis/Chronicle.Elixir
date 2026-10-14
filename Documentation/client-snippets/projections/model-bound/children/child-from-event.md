```elixir
defmodule MyApp.Events.MbChildrenChildFromEventConfigurationAdded do
  use Chronicle.Events.EventType, id: "mb-children-child-from-event-configuration-added"

  defstruct [:dashboard_id, :configuration_id, :name]
end

defmodule MyApp.Events.MbChildrenChildFromEventConfigurationRenamed do
  use Chronicle.Events.EventType, id: "mb-children-child-from-event-configuration-renamed"

  defstruct [:dashboard_id, :id, :name]
end

defmodule MyApp.ReadModels.MbChildrenChildFromEventConfiguration do
  defstruct id: nil, name: nil
end

defmodule MyApp.ReadModels.MbChildrenChildFromEventDashboard do
  use Chronicle.ReadModels.ReadModel,
    types: [configurations: {:list, MyApp.ReadModels.MbChildrenChildFromEventConfiguration}]

  defstruct id: nil, name: nil, configurations: []

  children :configurations, identified_by: :id do
    from MyApp.Events.MbChildrenChildFromEventConfigurationAdded,
      key: :configuration_id,
      parent_key: :dashboard_id,
      set: [id: :configuration_id, name: :name]

    # The child is also updated by an event that carries the id of the child itself and the
    # dashboard it belongs to.
    from MyApp.Events.MbChildrenChildFromEventConfigurationRenamed,
      key: :id,
      parent_key: :dashboard_id,
      set: [name: :name]
  end
end
```

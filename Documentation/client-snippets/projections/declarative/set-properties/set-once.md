```elixir title="Set a value only once"
defmodule MyApp.Events.DecSetOnceDocumentRevised do
  use Chronicle.Events.EventType, id: "dec-set-once-document-revised"

  defstruct title: ""
end

defmodule MyApp.ReadModels.DecSetOnceDocument do
  use Chronicle.ReadModels.ReadModel,
    types: [created: :datetime, last_revised: :datetime]

  defstruct original_title: nil, title: "", created_by: nil, created: nil, last_revised: nil
end

defmodule MyApp.Projections.DecSetOnceDocumentProjection do
  use Chronicle.Projections.Projection, model: MyApp.ReadModels.DecSetOnceDocument

  from MyApp.Events.DecSetOnceDocumentRevised,
    set_once: [
      original_title: :title,
      created_by: {:caused_by, :subject},
      created: :occurred
    ],
    set: [title: :title, last_revised: :occurred]
end
```

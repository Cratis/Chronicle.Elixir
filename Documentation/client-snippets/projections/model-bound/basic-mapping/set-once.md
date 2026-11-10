```elixir title="Model-bound set once"
defmodule MyApp.Events.MbSetOnceDocumentRevised do
  use Chronicle.Events.EventType, id: "mb-set-once-document-revised"

  defstruct title: ""
end

defmodule MyApp.ReadModels.MbSetOnceDocument do
  use Chronicle.ReadModels.ReadModel,
    types: [created: :datetime, last_revised: :datetime]

  alias MyApp.Events.MbSetOnceDocumentRevised

  defstruct original_title: nil, title: "", created_by: nil, created: nil, last_revised: nil

  from MbSetOnceDocumentRevised,
    set_once: [
      original_title: :title,
      created_by: {:caused_by, :subject},
      created: :occurred
    ],
    set: [title: :title, last_revised: :occurred]
end
```

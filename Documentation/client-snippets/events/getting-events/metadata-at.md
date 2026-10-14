```elixir
defmodule MyApp.MetadataAtReader do
  alias Chronicle.EventSequences.Streams

  # Call only after your application authorizes access to these events.
  def read do
    case Streams.get_metadata_at(42) do
      {:ok, metadata} ->
        IO.puts("#{metadata.event_stream_type}: #{metadata.resolved_caused_by.resolution}")

      {:error, :not_found} ->
        :ok
    end

    {:ok, batch} = Streams.get_metadata([42, 43])

    for entry <- batch do
      name = if entry.caused_by, do: entry.caused_by.name, else: "Name unavailable"
      IO.puts("#{entry.sequence_number}: #{name}")
    end
  end
end
```

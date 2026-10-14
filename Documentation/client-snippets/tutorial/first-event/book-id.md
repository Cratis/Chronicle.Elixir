```elixir
defmodule MyApp.BookId do
  use Chronicle.Concept, type: :uuid, event_source_id: true

  def new do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> = :crypto.strong_rand_bytes(16)

    value =
      :io_lib.format("~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b", [
        a,
        b,
        c,
        Bitwise.bor(0x8000, d),
        e
      ])
      |> IO.iodata_to_binary()

    %__MODULE__{value: value}
  end
end
```

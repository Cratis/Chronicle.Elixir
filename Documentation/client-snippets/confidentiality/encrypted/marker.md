```elixir
# Cratis.Chronicle.Confidentiality.encrypted/1,2,3 - imported automatically inside
# modules that `use Cratis.Chronicle.Events.EventType` or
# `use Cratis.Chronicle.ReadModels.ReadModel`. Marks one struct field.
#
#   defmacro encrypted(field, scope \\ :subject, details \\ "")
#
# Cratis.Chronicle.Concept.encrypted/0,1,2 - imported automatically inside modules
# that `use Cratis.Chronicle.Concept`. Marks the concept's value itself.
#
#   defmacro encrypted(scope \\ :subject, details \\ "")
```

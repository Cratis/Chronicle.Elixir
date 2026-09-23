```elixir
# Chronicle.Confidentiality.encrypted/1,2,3 - imported automatically inside
# modules that `use Chronicle.Events.EventType` or
# `use Chronicle.ReadModels.ReadModel`. Marks one struct field.
#
#   defmacro encrypted(field, scope \\ :subject, details \\ "")
#
# Chronicle.Concept.encrypted/0,1,2 - imported automatically inside modules
# that `use Chronicle.Concept`. Marks the concept's value itself.
#
#   defmacro encrypted(scope \\ :subject, details \\ "")
```

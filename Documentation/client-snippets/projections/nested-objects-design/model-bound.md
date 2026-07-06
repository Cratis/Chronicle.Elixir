```text
Elixir does not support this workflow yet.
The `from`/`join` options include a `:parent_key` for nested list-style
children, but there is no equivalent for a single nested sub-object that gets
cleared by a specific event. Track the client SDK issue before relying on
nested object projection from Elixir.
```

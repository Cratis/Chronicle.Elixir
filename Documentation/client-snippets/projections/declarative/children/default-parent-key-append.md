```elixir title="Append child event to parent"
defmodule MyApp.GroupMembershipWithDefaultParentKey do
  alias MyApp.Events.UserAddedWithDefaultParentKey

  def add_user_to_group(group_id, user_id, role) do
    Cratis.Chronicle.append(
      group_id,
      struct!(UserAddedWithDefaultParentKey, user_id: user_id, role: role)
    )
  end
end
```

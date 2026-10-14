```elixir title="Append child event with parent key"
defmodule MyApp.GroupMembershipWithEventParentKey do
  alias MyApp.Events.UserAddedWithEventParentKey

  def add_user_to_group(user_id, group_id, role) do
    Chronicle.append(
      user_id,
      struct!(UserAddedWithEventParentKey, group_id: group_id, user_id: user_id, role: role)
    )
  end
end
```

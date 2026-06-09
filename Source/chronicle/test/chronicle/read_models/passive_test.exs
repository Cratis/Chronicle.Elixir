# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.PassiveTest do
  use ExUnit.Case, async: true

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "passive-test-some-event"
    defstruct [:name]
  end

  defmodule ActiveReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil
    from SomeEvent, set: [id: :event_source_id, name: :name]
  end

  defmodule PassiveReadModel do
    use Chronicle.ReadModels.ReadModel, passive: true
    defstruct id: nil, name: nil
    from SomeEvent, set: [id: :event_source_id, name: :name]
  end

  describe "passive read models" do
    test "default read models are not passive" do
      refute ActiveReadModel.__chronicle_read_model__(:passive?)
    end

    test "read models declared with passive: true are passive" do
      assert PassiveReadModel.__chronicle_read_model__(:passive?)
    end
  end
end

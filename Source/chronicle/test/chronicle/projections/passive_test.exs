# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.PassiveTest do
  use ExUnit.Case, async: true

  defmodule SomeEvent do
    use Chronicle.Events.EventType, id: "passive-projection-test-some-event"
    defstruct [:name]
  end

  defmodule SomeReadModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, name: nil
  end

  defmodule ActiveProjection do
    use Chronicle.Projections.Projection, model: SomeReadModel
    from SomeEvent, set: [id: :event_source_id, name: :name]
  end

  defmodule PassiveProjection do
    use Chronicle.Projections.Projection, model: SomeReadModel, passive: true
    from SomeEvent, set: [id: :event_source_id, name: :name]
  end

  describe "passive declarative projections" do
    test "default projections are not passive" do
      refute ActiveProjection.__chronicle_projection__(:passive?)
    end

    test "projections declared with passive: true are passive" do
      assert PassiveProjection.__chronicle_projection__(:passive?)
    end
  end
end

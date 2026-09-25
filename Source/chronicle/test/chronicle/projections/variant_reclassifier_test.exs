# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Projections.VariantReclassifierTest do
  use ExUnit.Case, async: true

  alias Chronicle.Projections.GlobalHandlerPropertyNotOnVariant
  alias Chronicle.Projections.VariantMustDeclareEntersOnEvent
  alias Chronicle.Projections.VariantReclassifier
  alias Chronicle.Registration.Coordinator

  defmodule IssueCreated do
    use Chronicle.Events.EventType, id: "variant-reclassifier-test-issue-created"
    defstruct [:title]
  end

  defmodule PullRequestCreated do
    use Chronicle.Events.EventType, id: "variant-reclassifier-test-pull-request-created"
    defstruct [:pull_request_url]
  end

  defmodule BuildCompleted do
    use Chronicle.Events.EventType, id: "variant-reclassifier-test-build-completed"
    defstruct [:build_status]
  end

  defmodule TitleChanged do
    use Chronicle.Events.EventType, id: "variant-reclassifier-test-title-changed"
    defstruct [:title]
  end

  # Anchors the logical identity shared by every variant below. Never itself a read model.
  defmodule WorkItem do
  end

  defmodule BacklogItem do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, title: nil

    variant_of(WorkItem, key: :id)
    enters_on(IssueCreated)
    from(IssueCreated, set: [id: :event_source_id, title: :title])
  end

  defmodule PullRequestItem do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, title: nil, pull_request_url: nil, build_status: nil

    variant_of(WorkItem, key: :id)
    enters_on(PullRequestCreated)
    from(PullRequestCreated, set: [id: :event_source_id, pull_request_url: :pull_request_url])
    from(BuildCompleted, set: [build_status: :build_status])
  end

  defmodule UndeclaredVariant do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, title: nil

    variant_of(WorkItem, key: :id)
    from(IssueCreated, set: [id: :event_source_id, title: :title])
  end

  defmodule TitleHandler do
    use Chronicle.Projections.GlobalHandler, identity: WorkItem

    from(TitleChanged, set: [title: :title])
  end

  defmodule MismatchedHandler do
    use Chronicle.Projections.GlobalHandler, identity: WorkItem

    from(TitleChanged, set: [unrelated_property: :title])
  end

  # Declarative equivalent of BacklogItem/PullRequestItem - the read model is a pure struct and
  # the variant/entersOn declarations live on the separate projection module instead.
  defmodule DecWorkItem do
  end

  defmodule DecBacklogItemModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, title: nil
  end

  defmodule DecBacklogItemProjection do
    use Chronicle.Projections.Projection, model: DecBacklogItemModel

    variant_of(DecWorkItem, key: :id)
    enters_on(IssueCreated)
    from(IssueCreated, set: [id: :event_source_id, title: :title])
  end

  defmodule DecPullRequestItemModel do
    use Chronicle.ReadModels.ReadModel
    defstruct id: nil, pull_request_url: nil, build_status: nil
  end

  defmodule DecPullRequestItemProjection do
    use Chronicle.Projections.Projection, model: DecPullRequestItemModel

    variant_of(DecWorkItem, key: :id)
    enters_on(PullRequestCreated)

    from(PullRequestCreated,
      set: [id: :event_source_id, pull_request_url: :pull_request_url]
    )

    from(BuildCompleted, set: [build_status: :build_status])
  end

  defp entry_for(module) do
    definition =
      module
      |> Coordinator.build_projection_definition()
      |> Coordinator.apply_entering_key_overrides(module.__chronicle_read_model__(:enters_on))

    {module, module, definition, Coordinator.variant_metadata(module, :read_model)}
  end

  defp declarative_entry_for(module) do
    definition =
      module
      |> Coordinator.build_declarative_projection_definition()
      |> Coordinator.apply_entering_key_overrides(module.__chronicle_projection__(:enters_on))

    {module, module.__chronicle_projection__(:model), definition,
     Coordinator.variant_metadata(module, :projection)}
  end

  defp field(map, key), do: Map.get(map, key)
  defp event_type_id(event_module), do: event_module.__chronicle_event_type__(:id)

  defp find_by_event_id(entries, event_module) do
    Enum.find(entries, fn entry ->
      field(field(entry, :Key), :Id) == event_type_id(event_module)
    end)
  end

  defp has_event_id?(entries, event_module) do
    Enum.any?(entries, fn entry ->
      field(field(entry, :Key), :Id) == event_type_id(event_module)
    end)
  end

  describe "when a variant enters on its own event" do
    test "keeps the entering event as a create-or-update From handler" do
      [definition] = VariantReclassifier.apply([entry_for(BacklogItem)], [])

      issue_created = find_by_event_id(field(definition, :From), IssueCreated)
      assert issue_created
      assert field(field(issue_created, :Value), :Properties)["title"] == "title"
    end
  end

  describe "when a variant projects from an event that is not its entering event" do
    test "reclassifies it into an update-only self-referential join" do
      [_backlog, pull_request] =
        VariantReclassifier.apply([entry_for(BacklogItem), entry_for(PullRequestItem)], [])

      refute has_event_id?(field(pull_request, :From), BuildCompleted)

      build_completed_join = find_by_event_id(field(pull_request, :Join), BuildCompleted)
      assert build_completed_join

      join_value = field(build_completed_join, :Value)
      assert field(join_value, :On) == "id"
      assert field(join_value, :Key) == "$eventSourceId"
      # The read model property keeps its snake_case name; the event field is read by its
      # camelCase wire name.
      assert field(join_value, :Properties)["build_status"] == "buildStatus"
    end
  end

  describe "when two variants of the same identity are registered together" do
    test "cross-wires mutual exclusion between them" do
      [backlog, pull_request] =
        VariantReclassifier.apply([entry_for(BacklogItem), entry_for(PullRequestItem)], [])

      assert has_event_id?(field(backlog, :RemovedWith), PullRequestCreated)
      assert has_event_id?(field(pull_request, :RemovedWith), IssueCreated)
    end
  end

  describe "when a globalFor shared handler applies to a group" do
    test "merges its mapping into every variant" do
      [backlog, pull_request] =
        VariantReclassifier.apply(
          [entry_for(BacklogItem), entry_for(PullRequestItem)],
          [TitleHandler]
        )

      backlog_title_changed = find_by_event_id(field(backlog, :Join), TitleChanged)
      assert backlog_title_changed
      assert field(field(backlog_title_changed, :Value), :Properties)["title"] == "title"

      pull_request_title_changed = find_by_event_id(field(pull_request, :Join), TitleChanged)
      assert pull_request_title_changed
      assert field(field(pull_request_title_changed, :Value), :Properties)["title"] == "title"
    end
  end

  describe "when a variant does not declare an enters_on event" do
    test "raises VariantMustDeclareEntersOnEvent" do
      assert_raise VariantMustDeclareEntersOnEvent, fn ->
        VariantReclassifier.apply([entry_for(UndeclaredVariant)], [])
      end
    end
  end

  describe "when a globalFor shared handler maps to a property a variant does not have" do
    test "raises GlobalHandlerPropertyNotOnVariant" do
      assert_raise GlobalHandlerPropertyNotOnVariant, fn ->
        VariantReclassifier.apply(
          [entry_for(BacklogItem), entry_for(PullRequestItem)],
          [MismatchedHandler]
        )
      end
    end
  end

  describe "when two declarative variants of the same identity are registered together" do
    test "reclassifies the non-entering event and cross-wires mutual exclusion" do
      [backlog, pull_request] =
        VariantReclassifier.apply(
          [
            declarative_entry_for(DecBacklogItemProjection),
            declarative_entry_for(DecPullRequestItemProjection)
          ],
          []
        )

      refute has_event_id?(field(pull_request, :From), BuildCompleted)
      assert has_event_id?(field(pull_request, :Join), BuildCompleted)

      assert has_event_id?(field(backlog, :RemovedWith), PullRequestCreated)
      assert has_event_id?(field(pull_request, :RemovedWith), IssueCreated)
    end
  end
end

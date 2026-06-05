# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.DefinitionBuilder do
  @moduledoc """
  Immutable builder for webhook definitions.

  When no event types are configured explicitly, the builder uses all registered
  event types passed to `new/1`.
  """

  alias Chronicle.WebHooks.{Definition, EventType, Target}

  defstruct registered_event_types: [],
            event_types: [],
            headers: %{},
            event_sequence_id: "event-log",
            authorization: nil,
            replayable?: true,
            active?: true

  @type t :: %__MODULE__{
          registered_event_types: [module()],
          event_types: [module()],
          headers: %{optional(String.t()) => String.t()},
          event_sequence_id: String.t(),
          authorization: Target.authorization(),
          replayable?: boolean(),
          active?: boolean()
        }

  @doc """
  Creates a new definition builder.
  """
  @spec new([module()]) :: t()
  def new(registered_event_types \\ []) do
    %__MODULE__{registered_event_types: Enum.uniq(registered_event_types)}
  end

  @doc """
  Sets the event sequence id for the webhook.
  """
  @spec on_event_sequence(t(), String.t()) :: t()
  def on_event_sequence(%__MODULE__{} = builder, event_sequence_id)
      when is_binary(event_sequence_id) do
    %{builder | event_sequence_id: event_sequence_id}
  end

  @doc """
  Uses HTTP basic authentication.
  """
  @spec with_basic_auth(t(), String.t(), String.t()) :: t()
  def with_basic_auth(%__MODULE__{} = builder, username, password) do
    %{builder | authorization: {:basic, %{username: username, password: password}}}
  end

  @doc """
  Uses HTTP bearer-token authentication.
  """
  @spec with_bearer_token(t(), String.t()) :: t()
  def with_bearer_token(%__MODULE__{} = builder, token) do
    %{builder | authorization: {:bearer, %{token: token}}}
  end

  @doc """
  Uses OAuth client credentials authentication.
  """
  @spec with_oauth(t(), String.t(), String.t(), String.t()) :: t()
  def with_oauth(%__MODULE__{} = builder, authority, client_id, client_secret) do
    %{
      builder
      | authorization:
          {:oauth, %{authority: authority, client_id: client_id, client_secret: client_secret}}
    }
  end

  @doc """
  Adds or replaces a target header.
  """
  @spec with_header(t(), String.t(), String.t()) :: t()
  def with_header(%__MODULE__{} = builder, key, value) do
    %{builder | headers: Map.put(builder.headers, key, value)}
  end

  @doc """
  Adds an event type to the webhook definition.
  """
  @spec with_event_type(t(), module()) :: t()
  def with_event_type(%__MODULE__{} = builder, event_type) when is_atom(event_type) do
    %{builder | event_types: Enum.uniq(builder.event_types ++ [event_type])}
  end

  @doc """
  Marks the webhook as not replayable.
  """
  @spec not_replayable(t()) :: t()
  def not_replayable(%__MODULE__{} = builder), do: %{builder | replayable?: false}

  @doc """
  Marks the webhook as inactive.
  """
  @spec not_active(t()) :: t()
  def not_active(%__MODULE__{} = builder), do: %{builder | active?: false}

  @doc """
  Builds a webhook definition.
  """
  @spec build(t(), String.t(), String.t()) :: Definition.t()
  def build(%__MODULE__{} = builder, id, target_url)
      when is_binary(id) and is_binary(target_url) do
    if String.trim(target_url) == "" do
      raise ArgumentError, "webhook '#{id}' has an empty target URL"
    end

    event_type_modules =
      case builder.event_types do
        [] -> builder.registered_event_types
        modules -> modules
      end

    %Definition{
      id: id,
      event_sequence_id: builder.event_sequence_id,
      event_types: Enum.map(event_type_modules, &event_type_from_module/1),
      target: %Target{
        url: target_url,
        headers: builder.headers,
        authorization: builder.authorization
      },
      replayable?: builder.replayable?,
      active?: builder.active?
    }
  end

  defp event_type_from_module(module) do
    unless function_exported?(module, :__chronicle_event_type__, 1) do
      raise ArgumentError, "#{inspect(module)} is not a Chronicle event type"
    end

    id = module.__chronicle_event_type__(:id)

    if id in [nil, ""] do
      raise ArgumentError, "#{inspect(module)} has an invalid Chronicle event type id"
    end

    %EventType{
      id: id,
      generation: module.__chronicle_event_type__(:generation)
    }
  end
end

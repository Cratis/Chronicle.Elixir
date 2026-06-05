# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.WebHooks.Target do
  @moduledoc """
  Represents the delivery target for a webhook.
  """

  defstruct url: "", headers: %{}, authorization: nil

  @type authorization ::
          {:basic, %{username: String.t(), password: String.t()}}
          | {:bearer, %{token: String.t()}}
          | {:oauth, %{authority: String.t(), client_id: String.t(), client_secret: String.t()}}
          | nil

  @type t :: %__MODULE__{
          url: String.t(),
          headers: %{optional(String.t()) => String.t()},
          authorization: authorization()
        }
end

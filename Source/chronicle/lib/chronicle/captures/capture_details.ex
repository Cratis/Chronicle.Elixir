# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Captures.CaptureDetails do
  @moduledoc """
  A capture as reported by the Chronicle kernel: its id, name, compiled CDL declaration text,
  and whether it is running.
  """

  defstruct id: "", name: "", declaration: "", status: :stopped

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          declaration: String.t(),
          status: :stopped | :started
        }

  @doc false
  @spec from_proto(struct()) :: t()
  def from_proto(proto) do
    %__MODULE__{
      id: guid_to_string(Map.get(proto, :Id)),
      name: Map.get(proto, :Name, ""),
      declaration: Map.get(proto, :Declaration, ""),
      status: status_from_proto(Map.get(proto, :Status))
    }
  end

  defp status_from_proto(:Started), do: :started
  defp status_from_proto(_), do: :stopped

  defp guid_to_string(nil), do: ""
  defp guid_to_string(value) when is_binary(value), do: value

  defp guid_to_string(%{lo: lo, hi: hi}) when is_integer(lo) and is_integer(hi) do
    <<a::little-32, b::little-16, c::little-16, d::binary-size(2), e::binary-size(6)>> =
      <<lo::little-unsigned-64, hi::little-unsigned-64>>

    [
      Base.encode16(<<a::32>>, case: :lower),
      Base.encode16(<<b::16>>, case: :lower),
      Base.encode16(<<c::16>>, case: :lower),
      Base.encode16(d, case: :lower),
      Base.encode16(e, case: :lower)
    ]
    |> Enum.join("-")
  end

  defp guid_to_string(_), do: ""
end

# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Registration.RetryPolicy do
  @moduledoc """
  How registration with the kernel is retried: capped exponential backoff with jitter, a maximum
  number of attempts, and a distinction between failures worth retrying and failures that will
  never succeed. Mirrors the .NET client's `RegistrationRetryOptions` / `RegistrationBackoff`.

  Configure it with the `:registration` option of `Chronicle.Client`:

      {Chronicle.Client,
       registration: [initial_delay: 1_000, max_delay: 5_000, jitter: 0.2, max_attempts: 10]}

    * `:initial_delay` - the delay after the first failure in milliseconds (default `5_000`)
    * `:max_delay` - the cap of the exponential growth (default `5_000`, so by default the delay
      stays fixed at `:initial_delay`, as it always has; raise it to get growth)
    * `:multiplier` - growth factor between attempts (default `2`)
    * `:jitter` - fraction of the delay randomly added or removed, `0.0` to `1.0` (default `0.0`)
    * `:max_attempts` - give up after this many failed attempts (default `:infinity`)

  A registration the kernel rejects as invalid (a validation failure, an invalid argument) is not
  retried: repeating it cannot change the answer. It is reported as failed immediately.
  """

  defstruct initial_delay: 5_000,
            max_delay: 5_000,
            multiplier: 2,
            jitter: 0.0,
            max_attempts: :infinity

  @type t :: %__MODULE__{
          initial_delay: pos_integer(),
          max_delay: pos_integer(),
          multiplier: number(),
          jitter: float(),
          max_attempts: pos_integer() | :infinity
        }

  @doc "Builds a policy from `:registration` options."
  @spec new(keyword() | t() | nil) :: t()
  def new(nil), do: %__MODULE__{}
  def new(%__MODULE__{} = policy), do: policy
  def new(opts) when is_list(opts), do: struct!(__MODULE__, opts)

  @doc """
  The delay in milliseconds before attempt number `failed_attempts + 1`.

  `random` is a function returning a float in `[0.0, 1.0)`, injectable for tests.
  """
  @spec delay(t(), pos_integer(), (-> float())) :: non_neg_integer()
  def delay(%__MODULE__{} = policy, failed_attempts, random \\ &:rand.uniform/0)
      when failed_attempts >= 1 do
    base =
      min(
        policy.max_delay,
        round(policy.initial_delay * :math.pow(policy.multiplier, failed_attempts - 1))
      )

    spread = base * policy.jitter
    max(0, round(base + spread * (random.() * 2 - 1)))
  end

  @doc "Whether another attempt should be made after `failed_attempts` failures with `reason`."
  @spec retry?(t(), pos_integer(), term()) :: boolean()
  def retry?(%__MODULE__{max_attempts: max}, failed_attempts, reason) do
    retryable?(reason) and (max == :infinity or failed_attempts < max)
  end

  @doc "Whether a failure could succeed if repeated."
  @spec retryable?(term()) :: boolean()
  def retryable?({:validation_results, _}), do: false
  def retryable?(%GRPC.RPCError{status: status}), do: status not in [3, 12]
  def retryable?(_), do: true
end

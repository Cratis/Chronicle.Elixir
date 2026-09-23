# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Confidentiality.PiiAndEncryptedCombinedNotSupported do
  @moduledoc """
  Raised when a property, or the concept it resolves metadata from, carries
  both `Chronicle.Compliance.pii/1,2` and `Chronicle.Confidentiality.encrypted/1,2,3`.

  This is not merely redundant - it corrupts the value. The kernel applies
  every matching handler for a property in sequence, so a value marked both
  ways is encrypted first under the PII key and then again under the
  Encrypted key; releasing it decrypts with the wrong key against
  ciphertext, which fails loudly (a padding/authentication error) rather
  than returning a wrong value. A value needs exactly one protection: `pii`
  for personal data with a lawful basis for erasure, `encrypted` for an
  operational secret with none.
  """

  defexception [:message, :field]

  @impl true
  def exception(opts) do
    field = Keyword.fetch!(opts, :field)

    %__MODULE__{
      field: field,
      message:
        "'#{inspect(field)}' carries both pii and encrypted. A value needs exactly one " <>
          "protection - combining them would encrypt it twice, under two different keys, " <>
          "and it cannot be released correctly. Choose pii for personal data with a lawful " <>
          "basis for erasure, or encrypted for an operational secret with none."
    }
  end
end

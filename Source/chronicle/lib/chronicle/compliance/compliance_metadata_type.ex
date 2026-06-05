# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Compliance.ComplianceMetadataType do
  @moduledoc """
  Identifies a kind of compliance metadata that can be attached to a property
  or type in a generated JSON schema.

  The Chronicle kernel matches the `metadataType` value carried in a schema's
  `compliance` array against its registered compliance handlers. The value is a
  GUID; for personally identifiable information it is the well-known PII type id
  (the same value the C# and TypeScript clients use).
  """

  @pii "cae5580e-83d6-44dc-9d7a-a72e8a2f17d7"

  @doc """
  The compliance metadata type id for Personally Identifiable Information (PII)
  according to the definition of personal data in GDPR.

  Returns the GUID the Chronicle kernel uses to select its PII (GDPR) compliance
  handler, which encrypts the adorned values.
  """
  @spec pii() :: String.t()
  def pii, do: @pii
end

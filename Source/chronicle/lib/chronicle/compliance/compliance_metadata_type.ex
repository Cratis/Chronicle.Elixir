# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Compliance.ComplianceMetadataType do
  @moduledoc """
  Identifies a kind of compliance metadata that can be attached to a property
  or type in a generated JSON schema.

  The Chronicle kernel matches the `metadataType` value carried in a schema's
  `compliance` array against its registered compliance handlers. The value is a
  string; for personally identifiable information it is the well-known `"PII"`
  string (the same value the C# and TypeScript clients use).
  """

  @pii "PII"

  @doc """
  The compliance metadata type for Personally Identifiable Information (PII)
  according to the definition of personal data in GDPR.

  Returns the string the Chronicle kernel uses to select its PII (GDPR) compliance
  handler, which encrypts the adorned values.
  """
  @spec pii() :: String.t()
  def pii, do: @pii
end

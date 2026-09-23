# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Confidentiality.SecurityMetadataType do
  @moduledoc """
  Identifies a kind of security metadata that can be attached to a property or
  type in a generated JSON schema.

  This is the security counterpart to `Chronicle.Compliance.ComplianceMetadataType`
  - a deliberately separate module rather than a shared one. The Chronicle
  kernel matches the `metadataType` value carried in a schema's `security`
  array against its registered security handlers, keyed by
  `EncryptionScope`: `EncryptedSubject`, `EncryptedNamespace`, or
  `EncryptedGlobal` — the same three strings the C#, TypeScript, and Kotlin
  clients use.
  """

  @encrypted_subject "EncryptedSubject"
  @encrypted_namespace "EncryptedNamespace"
  @encrypted_global "EncryptedGlobal"

  @doc """
  The security metadata type for a value encrypted under a key provisioned
  per compliance identity - the same identity, resolved the same way, a
  `Chronicle.Compliance.pii/1,2` value on the same document uses. This is
  what `encrypted/1,2,3` (with no explicit scope, or `:subject`) resolves to.
  """
  @spec encrypted_subject() :: String.t()
  def encrypted_subject, do: @encrypted_subject

  @doc """
  The security metadata type for a value encrypted under a key provisioned
  once per event store namespace. This is what `encrypted(field, :namespace)`
  resolves to.
  """
  @spec encrypted_namespace() :: String.t()
  def encrypted_namespace, do: @encrypted_namespace

  @doc """
  The security metadata type for a value encrypted under a key provisioned
  once for the whole Chronicle installation. This is what
  `encrypted(field, :global)` resolves to.
  """
  @spec encrypted_global() :: String.t()
  def encrypted_global, do: @encrypted_global

  @doc """
  Maps an `EncryptionScope` atom (`:subject`, `:namespace`, or `:global`) to
  the metadata type string the kernel's value handlers dispatch on.
  """
  @spec for_scope(:subject | :namespace | :global) :: String.t()
  def for_scope(:subject), do: @encrypted_subject
  def for_scope(:namespace), do: @encrypted_namespace
  def for_scope(:global), do: @encrypted_global
end

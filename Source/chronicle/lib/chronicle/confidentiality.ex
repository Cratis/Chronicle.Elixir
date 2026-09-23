# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Confidentiality do
  @moduledoc """
  Plain-confidentiality encryption for marking event and read model fields as
  needing encryption at rest without being personal data — mirroring the
  `@encrypted` decorator in the C#, TypeScript, and Kotlin clients.

  This is deliberately separate from `Chronicle.Compliance` rather than
  layered on top of it. Marking a field `pii/1,2` causes the Chronicle kernel
  to encrypt it under a compliance (GDPR) key *and* enroll it in
  right-to-erasure; marking a field `encrypted/1,2,3` causes the kernel to
  encrypt it under a completely separate, disjoint key with no erasure
  obligation at all. Use `encrypted/1,2,3` for an operational secret - an API
  key, a webhook signing secret, a partner credential. Use `pii/1,2` instead
  when the value is personal data about a natural person. The two are not
  interchangeable: marking a secret `pii/1,2` would make it erasable on a
  request that was never about it; marking personal data `encrypted/1,2,3`
  would encrypt it but never erase it.

  A field cannot carry both `pii/1,2` and `encrypted/1,2,3` -
  `Chronicle.Schemas.JsonSchemaGenerator` raises
  `Chronicle.Confidentiality.PiiAndEncryptedCombinedNotSupported` at
  schema-generation time if it finds both resolving for the same leaf. This
  is not merely redundant - the kernel applies every matching handler in
  sequence, so a value marked both ways would be encrypted twice, under two
  different keys, and could never be released correctly.

  The `encrypted/1,2,3` macro is imported automatically inside modules that
  `use Chronicle.Events.EventType` or `use Chronicle.ReadModels.ReadModel`:

      defmodule MyApp.Events.PartnerIntegrationConfigured do
        use Chronicle.Events.EventType, id: "partner-integration-configured"
        defstruct [:partner_name, :api_key]

        encrypted :api_key, :subject, "Partner API key"
      end

  Each marked field is exposed through the module's
  `__chronicle_encrypted__/0` accessor as `{field, scope, details}` tuples.

  There is deliberately no erasure operation for `encrypted/1,2,3` values -
  the kernel's compliance erasure (`Chronicle.Compliance.delete_encryption_key/2`)
  already refuses to act on an identifier belonging to an encrypted value's
  disjoint keyspace, so this module exposes no equivalent entry point.
  """

  @doc """
  Marks a struct field as needing plain-confidentiality encryption at rest.

  Accumulates the field into the module's `@chronicle_encrypted` attribute.

    * `scope` — the `EncryptionScope` the key is provisioned under: `:subject`
      (default), `:namespace`, or `:global`. See the module documentation on
      `Chronicle.Confidentiality.SecurityMetadataType` for what each means.
    * `details` — an optional human-readable explanation of why the field
      needs encryption, and defaults to an empty string.
  """
  defmacro encrypted(field, scope \\ :subject, details \\ "") do
    quote do
      @chronicle_encrypted {unquote(field), unquote(scope), unquote(details)}
    end
  end
end

# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Compliance do
  @moduledoc """
  Compliance support for marking event and read model fields as containing
  sensitive data, mirroring the `@pii` decorator in the C# and TypeScript clients.

  Marking a field as PII causes the Chronicle kernel to encrypt that field's
  value using compliance-aware (GDPR) encryption. The marking is carried to the
  kernel as `compliance` metadata embedded in the generated JSON schema for the
  event type or read model — see `Chronicle.Schemas.JsonSchemaGenerator`.

  The `pii/1` and `pii/2` macros are imported automatically inside modules that
  `use Chronicle.Events.EventType` or `use Chronicle.ReadModels.ReadModel`:

      defmodule MyApp.Events.CustomerRegistered do
        use Chronicle.Events.EventType, id: "customer-registered"
        defstruct [:customer_id, :email, :full_name]

        pii :email, "Customer email address"
        pii :full_name
      end

  Each marked field is exposed through the module's `__chronicle_pii__/0`
  accessor as `{field, details}` tuples.
  """

  @doc """
  Marks a struct field as containing Personally Identifiable Information (PII).

  Accumulates the field into the module's `@chronicle_pii` attribute. `details`
  is an optional human-readable explanation of why the field is classified as
  PII and defaults to an empty string.
  """
  defmacro pii(field, details \\ "") do
    quote do
      @chronicle_pii {unquote(field), unquote(details)}
    end
  end
end

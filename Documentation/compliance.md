---
sharedTopicBridge: true
---

# Compliance

Compliance and PII handling are shared Chronicle topics. The shared docs own the concepts, storage behavior, and client-tabbed examples.

- [Compliance](/chronicle/compliance/)
- [PII](/chronicle/compliance/pii/)
- [Compliance in read models](/chronicle/compliance/read-models/)
- [Elixir client setup](./get-started.md)

## Erasure and re-enrollment

`Chronicle.Compliance.delete_encryption_key/2` is the right-to-erasure operation for a PII subject.
Deleting a key does not by itself permit a replacement: until the kernel is told a new key is
allowed, new PII values for that subject are rejected. When the subject has legitimately returned,
authorize a new key with `Chronicle.Compliance.allow_new_encryption_key_for/2`:

```elixir
:ok = Chronicle.Compliance.delete_encryption_key("customer-42")

# later, the person registers again
:ok = Chronicle.Compliance.allow_new_encryption_key_for("customer-42")
```

A kernel that does not support the operation returns `{:error, :not_supported}`.

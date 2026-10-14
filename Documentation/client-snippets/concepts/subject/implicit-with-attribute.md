```elixir
defmodule MyApp.Events.SubjectShippingAddressChangedWithImplicitSubject do
  # `subject:` names the field that holds the data subject, so the subject is
  # derived from `customer_id` and no explicit subject is needed on append.
  use Chronicle.Events.EventType,
    id: "subject-shipping-address-changed-with-implicit-subject",
    subject: :customer_id

  defstruct [:order_id, :customer_id, :street, :city]

  pii(:street)
  pii(:city)
end

defmodule MyApp.SubjectImplicitSubjectService do
  alias MyApp.Events.SubjectShippingAddressChangedWithImplicitSubject

  def change_address(order_id, customer_id, street, city) do
    Chronicle.append(
      order_id,
      %SubjectShippingAddressChangedWithImplicitSubject{
        order_id: order_id,
        customer_id: customer_id,
        street: street,
        city: city
      }
    )
  end
end
```

# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample do
  @moduledoc """
  Interactive employee-focused Chronicle sample.
  """

  alias ConsoleSample.Employees
  alias ConsoleSample.Employees.Person

  alias ConsoleSample.Events.{
    CustomerAddressUpdated,
    CustomerRegistered,
    EmployeeEmailSet,
    EmployeeMoved,
    EmployeePromoted
  }

  alias ConsoleSample.Projections.EmployeeDetails
  alias ConsoleSample.ReadModels.{Customer, EmployeeList, EmployeeState}
  alias Chronicle.ReadModels
  alias Chronicle.Transactions.UnitOfWork
  alias Chronicle.Auditing.CausationManager
  alias Chronicle.Identity
  alias Chronicle.Identities
  alias Chronicle.ExternalServices
  alias Chronicle.ExternalServices.DefinitionBuilder
  alias Chronicle.EventSequences.EventLog

  @titles [
    "Software Engineer",
    "Senior Engineer",
    "Principal Engineer",
    "Engineering Manager",
    "Architect"
  ]

  @addresses [
    %{address: "221B Baker Street", city: "London", zip_code: "NW1 6XE", country: "UK"},
    %{
      address: "1600 Amphitheatre Parkway",
      city: "Mountain View",
      zip_code: "94043",
      country: "USA"
    },
    %{address: "1 Infinite Loop", city: "Cupertino", zip_code: "95014", country: "USA"},
    %{address: "5 Wall Street", city: "New York", zip_code: "10005", country: "USA"}
  ]

  # Three mock users whose identity is attached to every append they trigger.
  # Press I in the console to cycle through them.
  @users [
    Identity.new("u0000001-0000-0000-0000-000000000000", "Alice Smith", "alice.smith"),
    Identity.new("u0000002-0000-0000-0000-000000000000", "Bob Jones", "bob.jones"),
    Identity.system()
  ]

  @sample_customer %{
    id: "c0000001-0000-0000-0000-000000000000",
    full_name: "Eve Jackson",
    email: "eve.jackson@example.com",
    phone_number: "+1-202-555-0143",
    street_address: "742 Evergreen Terrace",
    city: "Springfield",
    postal_code: "49007",
    country: "USA"
  }

  @spec run() :: no_return()
  def run do
    config = Chronicle.Client.config()

    case Chronicle.Connections.Lifecycle.wait_until(config.lifecycle, :registered, 30_000) do
      :ok -> :ok
      {:error, :timeout} -> IO.puts("[warn] Chronicle not yet registered — proceeding anyway")
    end

    wait_for_seeded_employees(40)

    print_seeded_employee_status()
    write_instructions()
    write_selected_employee(0, 0)

    status =
      try do
        with_terminal_mode(fn -> loop(0, 0) end)
        0
      rescue
        error ->
          IO.puts("\nUnhandled error: #{Exception.message(error)}")
          1
      end

    System.stop(status)

    receive do
    after
      :infinity -> :ok
    end
  end

  defp loop(selected_index, user_index) do
    case read_key() do
      "" ->
        IO.puts("\nExiting...")

      "q" ->
        IO.puts("\nExiting...")

      "1" ->
        write_selected_employee(0, user_index)
        loop(0, user_index)

      "2" ->
        write_selected_employee(1, user_index)
        loop(1, user_index)

      "3" ->
        write_selected_employee(2, user_index)
        loop(2, user_index)

      "i" ->
        next_user_index = rem(user_index + 1, length(@users))
        write_selected_user(next_user_index)
        loop(selected_index, next_user_index)

      "p" ->
        promote(selected_employee!(selected_index), selected_user!(user_index))
        loop(selected_index, user_index)

      "a" ->
        move(selected_employee!(selected_index), selected_user!(user_index))
        loop(selected_index, user_index)

      "e" ->
        set_email(selected_employee!(selected_index), selected_user!(user_index))
        loop(selected_index, user_index)

      "u" ->
        steal_email(selected_index, selected_user!(user_index))
        loop(selected_index, user_index)

      "r" ->
        show_employee_read_model(selected_employee!(selected_index))
        loop(selected_index, user_index)

      "j" ->
        show_employee_model_bound_projection(selected_employee!(selected_index))
        loop(selected_index, user_index)

      "k" ->
        show_employee_list_projection(selected_employee!(selected_index))
        loop(selected_index, user_index)

      "t" ->
        transact(selected_index, selected_user!(user_index))
        loop(selected_index, user_index)

      "c" ->
        register_customer_with_pii(selected_user!(user_index))
        loop(selected_index, user_index)

      "v" ->
        show_customer_read_model()
        loop(selected_index, user_index)

      "x" ->
        register_external_service()
        loop(selected_index, user_index)

      "n" ->
        rename_current_user(selected_user!(user_index))
        loop(selected_index, user_index)

      "w" ->
        promote_and_wait_for_completion(selected_employee!(selected_index), selected_user!(user_index))
        loop(selected_index, user_index)

      "d" ->
        redact_last_event_for_employee(selected_employee!(selected_index))
        loop(selected_index, user_index)

      "g" ->
        gdpr_erase_customer()
        loop(selected_index, user_index)

      "h" ->
        write_instructions()
        loop(selected_index, user_index)

      "?" ->
        write_instructions()
        loop(selected_index, user_index)

      _other ->
        loop(selected_index, user_index)
    end
  end

  defp promote(%Person{} = person, %Identity{} = user) do
    title = random_from(@titles)
    setup_causation(user, "ConsoleSample.Commands.Promote", %{employee_id: person.id})

    case Chronicle.append(person.id, %EmployeePromoted{new_title: title}) do
      :ok ->
        IO.puts(
          "\n[#{person.id}] Promoted #{full_name(person)} to '#{title}' at sequence #{tail_sequence(person.id)}  [caused-by: #{user.user_name}]"
        )

      {:error, reason} ->
        IO.puts(
          "\n[#{person.id}] Could not promote #{full_name(person)}: #{format_reason(reason)}"
        )
    end
  end

  defp move(%Person{} = person, %Identity{} = user) do
    address = random_from(@addresses)
    setup_causation(user, "ConsoleSample.Commands.Move", %{employee_id: person.id})

    case Chronicle.append(person.id, %EmployeeMoved{
           address: address.address,
           city: address.city,
           zip_code: address.zip_code,
           country: address.country
         }) do
      :ok ->
        IO.puts(
          "\n[#{person.id}] Moved #{full_name(person)} to #{address.address}, #{address.city} at sequence #{tail_sequence(person.id)}  [caused-by: #{user.user_name}]"
        )

      {:error, reason} ->
        IO.puts("\n[#{person.id}] Could not move #{full_name(person)}: #{format_reason(reason)}")
    end
  end

  defp set_email(%Person{} = person, %Identity{} = user) do
    email = Employees.email_for(person)
    setup_causation(user, "ConsoleSample.Commands.SetEmail", %{employee_id: person.id})

    case Chronicle.append(person.id, %EmployeeEmailSet{email: email}) do
      :ok ->
        IO.puts(
          "\n[#{person.id}] Set #{full_name(person)}'s email to #{email} at sequence #{tail_sequence(person.id)}  [caused-by: #{user.user_name}]"
        )

      {:error, reason} ->
        IO.puts("\n[#{person.id}] Could not set email: #{format_reason(reason)}")
    end
  end

  defp steal_email(selected_index, %Identity{} = user) do
    person = selected_employee!(selected_index)
    victim = selected_employee!(rem(selected_index + 1, length(Employees.all())))
    email = Employees.email_for(victim)
    setup_causation(user, "ConsoleSample.Commands.SetEmail", %{employee_id: person.id})

    case Chronicle.append(person.id, %EmployeeEmailSet{email: email}) do
      :ok ->
        IO.puts(
          "\n[#{person.id}] Unexpectedly took #{email} at sequence #{tail_sequence(person.id)}  [caused-by: #{user.user_name}]"
        )

      {:error, reason} ->
        IO.puts(
          "\n[#{person.id}] Rejected taking #{victim.first_name}'s email (#{email}): #{format_reason(reason)}"
        )
    end
  end

  defp transact(selected_index, %Identity{} = user) do
    selected = selected_employee!(selected_index)
    also_update = selected_employee!(rem(selected_index + 1, length(Employees.all())))
    selected_title = random_from(@titles)
    selected_address = random_from(@addresses)
    second_title = random_from(@titles)

    # Set up identity and causation once — all appends within the unit of work share this context.
    setup_causation(user, "ConsoleSample.Commands.BulkUpdate", %{
      employees: [selected.id, also_update.id]
    })

    unit_of_work = Chronicle.begin_unit_of_work()

    try do
      :ok = Chronicle.append(selected.id, %EmployeePromoted{new_title: selected_title})

      :ok =
        Chronicle.append_many(selected.id, [
          %EmployeeMoved{
            address: selected_address.address,
            city: selected_address.city,
            zip_code: selected_address.zip_code,
            country: selected_address.country
          }
        ])

      :ok = Chronicle.append(also_update.id, %EmployeePromoted{new_title: second_title})

      case UnitOfWork.commit(unit_of_work) do
        :ok ->
          IO.puts(
            "\n[transaction] Committed staged events for #{full_name(selected)} and #{full_name(also_update)}  [caused-by: #{user.user_name}]"
          )

        {:error, reason} ->
          IO.puts("\n[transaction] Failed committing staged events: #{format_reason(reason)}")
      end
    after
      if not UnitOfWork.is_completed?(unit_of_work) do
        UnitOfWork.rollback(unit_of_work)
      end
    end
  end

  defp register_customer_with_pii(%Identity{} = user) do
    case Chronicle.has_events_for?(@sample_customer.id) do
      {:ok, true} ->
        IO.puts("\n[pii] #{@sample_customer.full_name} is already registered.")

      {:ok, false} ->
        setup_causation(user, "ConsoleSample.Commands.RegisterCustomer", %{
          customer_id: @sample_customer.id
        })

        events = [
          %CustomerRegistered{
            customer_id: @sample_customer.id,
            full_name: @sample_customer.full_name,
            email: @sample_customer.email,
            phone_number: @sample_customer.phone_number
          },
          %CustomerAddressUpdated{
            customer_id: @sample_customer.id,
            street_address: @sample_customer.street_address,
            city: @sample_customer.city,
            postal_code: @sample_customer.postal_code,
            country: @sample_customer.country
          }
        ]

        # The subject identifies the encryption key the Chronicle kernel uses for
        # PII-adorned fields. Without a subject, compliance (PII) encryption is skipped.
        case Chronicle.append_many(@sample_customer.id, events, subject: @sample_customer.id) do
          :ok ->
            IO.puts(
              "\n[pii] Registered #{@sample_customer.full_name} (#{@sample_customer.id}) with customer data events up to sequence #{tail_sequence(@sample_customer.id)}  [caused-by: #{user.user_name}]"
            )

          {:error, reason} ->
            IO.puts(
              "\n[pii] Could not register #{@sample_customer.full_name}: #{format_reason(reason)}"
            )
        end

      {:error, reason} ->
        IO.puts("\n[pii] Could not check customer state: #{format_reason(reason)}")
    end
  end

  # Appends and then waits (up to a timeout, default 5s) for every observer affected
  # by the append — reactors, reducers, projections — to actually process it, instead
  # of returning as soon as the event is durably stored. Useful when a caller needs
  # "read your own write" consistency against a read model right after appending.
  # Mirrors the C# client's AppendResult.WaitForCompletion().
  defp promote_and_wait_for_completion(%Person{} = person, %Identity{} = user) do
    title = random_from(@titles)
    setup_causation(user, "ConsoleSample.Commands.Promote", %{employee_id: person.id})

    case EventLog.append_and_wait_for_completion(person.id, %EmployeePromoted{new_title: title}) do
      {:ok, %{success: true, failed_partitions: []}} ->
        IO.puts(
          "\n[wait-for-completion] Promoted #{full_name(person)} to '#{title}' and confirmed every observer caught up  [caused-by: #{user.user_name}]"
        )

      {:ok, %{success: false, failed_partitions: failed_partitions}} ->
        IO.puts(
          "\n[wait-for-completion] Promoted #{full_name(person)} to '#{title}', but #{length(failed_partitions)} observer(s) failed or timed out."
        )

      {:error, reason} ->
        IO.puts(
          "\n[wait-for-completion] Could not promote #{full_name(person)}: #{format_reason(reason)}"
        )
    end
  end

  # Permanently redacts the most recent event for the selected employee. Unlike
  # compliance encryption/PII masking (which conceal a value but stay reversible via
  # key rotation), redact/3 overwrites the event's content in the log for good — a
  # destructive, irreversible erasure for genuine "this event should never have been
  # recorded" cases (e.g. a GDPR Article 17 request against a single fact). Mirrors
  # the C# and TypeScript clients' IEventSequence.Redact().
  defp redact_last_event_for_employee(%Person{} = person) do
    case Chronicle.get_tail_sequence_number(person.id) do
      {:ok, 0} ->
        IO.puts("\n[redact] #{full_name(person)} has no events yet.")

      {:ok, sequence_number} ->
        reason = "Console sample demo: redact-on-demand for #{full_name(person)}"

        case EventLog.redact(sequence_number, reason) do
          :ok ->
            IO.puts(
              "\n[redact] Permanently redacted event ##{sequence_number} for #{full_name(person)}. This cannot be undone — its content is gone from the log."
            )

          {:error, reason} ->
            IO.puts("\n[redact] Could not redact: #{format_reason(reason)}")
        end

      {:error, reason} ->
        IO.puts("\n[redact] Could not determine the tail sequence number: #{format_reason(reason)}")
    end
  end

  # Permanently redacts EVERY event for the sample customer's event source in one
  # call — a bulk GDPR "right to be forgotten" erasure, as opposed to the single-event
  # redact above. Passing a list of event type modules as the fourth argument would
  # narrow this to specific event types only; omitting it (as here) redacts everything
  # recorded for the event source. This is destructive and irreversible.
  defp gdpr_erase_customer do
    reason = "Console sample demo: customer requested full erasure under GDPR"

    case EventLog.redact_for_event_source(@sample_customer.id, reason) do
      :ok ->
        IO.puts(
          "\n[redact] Permanently erased every event for customer #{@sample_customer.full_name} (#{@sample_customer.id}). Press V afterward to see the read model reflect the erasure."
        )

      {:error, reason} ->
        IO.puts("\n[redact] Could not erase customer events: #{format_reason(reason)}")
    end
  end

  defp show_employee_read_model(%Person{} = person) do
    case ReadModels.get_instance_by_id(EmployeeState, person.id) do
      {:ok, nil} ->
        IO.puts("\n[read-model] No EmployeeState found for #{full_name(person)}")

      {:ok, state} ->
        IO.puts(
          "\n[read-model] #{full_name(person)}: #{state.title} <#{blank_as(state.email, "no email yet")}> @ #{blank_as(state.address, "no address yet")}"
        )

      {:error, reason} ->
        IO.puts("\n[read-model] Could not read #{full_name(person)}: #{format_reason(reason)}")
    end
  end

  defp show_employee_model_bound_projection(%Person{} = person) do
    case ReadModels.get_instance_by_id(EmployeeDetails, person.id) do
      {:ok, nil} ->
        IO.puts("\n[projection:model-bound] No EmployeeDetails found for #{full_name(person)}")

      {:ok, state} ->
        IO.puts(
          "\n[projection:model-bound] #{full_name(person)}: #{state.title} @ #{blank_as(state.address, "no address yet")}"
        )

      {:error, reason} ->
        IO.puts(
          "\n[projection:model-bound] Could not read #{full_name(person)}: #{format_reason(reason)}"
        )
    end
  end

  defp show_employee_list_projection(%Person{} = person) do
    case ReadModels.get_instance_by_id(EmployeeList, person.id) do
      {:ok, nil} ->
        IO.puts("\n[projection:declarative] No EmployeeList entry found for #{full_name(person)}")

      {:ok, entry} ->
        IO.puts(
          "\n[projection:declarative] #{entry.first_name} #{entry.last_name} — #{entry.title}"
        )

      {:error, reason} ->
        IO.puts(
          "\n[projection:declarative] Could not read #{full_name(person)}: #{format_reason(reason)}"
        )
    end
  end

  defp show_customer_read_model do
    case ReadModels.get_instance_by_id(Customer, @sample_customer.id) do
      {:ok, nil} ->
        IO.puts(
          "\n[pii] No Customer read model found for #{@sample_customer.id}. Append the customer events first."
        )

      {:ok, customer} ->
        IO.puts("\nCustomer read model for #{customer.id}:")
        IO.puts(format_customer_field("Full name", customer.full_name, true))
        IO.puts(format_customer_field("Email", customer.email, true))
        IO.puts(format_customer_field("Phone number", customer.phone_number, true))
        IO.puts(format_customer_field("Street address", customer.street_address, true))
        IO.puts(format_customer_field("City", customer.city, true))
        IO.puts(format_customer_field("Postal code", customer.postal_code, true))
        IO.puts(format_customer_field("Country", customer.country, false))
        IO.puts(format_customer_field("Customer number", customer.customer_number, false))
        IO.puts(format_customer_field("Account status", customer.account_status, false))
        IO.puts(format_customer_field("Total orders", customer.total_orders, false))

        IO.puts(
          "  PII fields are marked above so you can identify which values need extra protection."
        )

      {:error, reason} ->
        IO.puts("\n[pii] Could not read the customer model: #{format_reason(reason)}")
    end
  end

  # Registers an HTTP external service the Chronicle kernel can call on our behalf —
  # e.g. from a capture. Registration is administrative (no event source, no identity).
  defp register_external_service do
    result =
      ExternalServices.register("CustomersApi", fn builder ->
        builder
        |> DefinitionBuilder.http("https://api.example.com")
        |> DefinitionBuilder.with_bearer_token(external_service_token())
        |> DefinitionBuilder.with_header("X-Tenant", "acme")
      end)

    case result do
      :ok ->
        IO.puts(
          "\n[external-services] Registered 'CustomersApi' as an HTTP service with bearer-token auth."
        )

      {:error, reason} ->
        IO.puts("\n[external-services] Could not register CustomersApi: #{format_reason(reason)}")
    end
  end

  defp external_service_token do
    System.get_env("CUSTOMERS_API_TOKEN") || "demo-token"
  end

  # Renames an identity by its stable subject. This changes only the display name — every
  # event this identity already caused resolves the new name, since the name isn't stored
  # with the event itself.
  defp rename_current_user(%Identity{} = user) do
    new_name = "#{user.name} ##{:rand.uniform(1000)}"

    case Identities.rename(user.subject, new_name) do
      :ok ->
        IO.puts(
          "\n[identities] Renamed identity @#{user.user_name} to '#{new_name}'. Past and future events caused by this identity now show the new name."
        )

      {:error, reason} ->
        IO.puts(
          "\n[identities] Could not rename identity @#{user.user_name}: #{format_reason(reason)}"
        )
    end
  end

  # Sets the process-scoped identity and rebuilds the causation chain for the next append.
  # Identity and causation are stored with every event written to the Chronicle event log,
  # enabling full auditability of who triggered each state change and what command caused it.
  defp setup_causation(%Identity{} = user, command, properties) do
    Chronicle.set_identity(user)
    CausationManager.clear()
    CausationManager.define_root(%{source: "console-sample"})
    CausationManager.add(command, properties)
  end

  defp print_seeded_employee_status do
    Enum.each(Employees.all(), fn employee ->
      status =
        case Chronicle.has_events_for?(employee.id) do
          {:ok, true} -> "seeded"
          {:ok, false} -> "missing"
          {:error, reason} -> "error: #{format_reason(reason)}"
        end

      IO.puts("Seeder status for #{full_name(employee)} (#{employee.id}): #{status}")
    end)
  end

  defp wait_for_seeded_employees(0), do: :ok

  defp wait_for_seeded_employees(attempts_left) do
    if Enum.all?(Employees.all(), &employee_seeded?/1) do
      :ok
    else
      Process.sleep(500)
      wait_for_seeded_employees(attempts_left - 1)
    end
  end

  defp employee_seeded?(%Person{id: id}) do
    match?({:ok, true}, Chronicle.has_events_for?(id))
  rescue
    _ -> false
  end

  defp write_instructions do
    IO.puts(
      [
        "",
        "Use 1-3 to select an employee. Then:",
        "  P = Promote          A = Move (change address)",
        "  E = Set email        U = Try to take the next employee's email (constraint violation)",
        "  R = Read model       T = Transactional update",
        "  J = Model-bound projection       K = Declarative projection",
        "  C = Register customer with PII   V = View customer PII read model",
        "  X = Register external service    N = Rename current user's identity",
        "  W = Promote and wait for observer completion",
        "  D = Redact selected employee's last event (permanent, destructive)",
        "  G = GDPR bulk-erase all customer events (permanent, destructive)",
        "  I = Switch user (cycle: Alice Smith → Bob Jones → System)",
        "  H or ? = Show this menu          Q = Quit",
        ""
      ]
      |> Enum.join("\n")
    )
  end

  defp write_selected_employee(emp_index, user_index) do
    person = selected_employee!(emp_index)
    user = selected_user!(user_index)
    IO.puts("Selected  [#{emp_index + 1}] #{full_name(person)} (#{person.id})")
    IO.puts("Acting as [#{user_index + 1}] #{user.name} (@#{user.user_name})")
  end

  defp write_selected_user(user_index) do
    user = selected_user!(user_index)
    IO.puts("\nSwitched to user [#{user_index + 1}] #{user.name} (@#{user.user_name})")
  end

  defp with_terminal_mode(fun) do
    # Use `sh -c "... < /dev/tty"` so stty operates on the controlling terminal
    # rather than on the Erlang port that System.cmd connects as stdin by default.
    original_mode =
      case System.find_executable("sh") do
        nil ->
          nil

        _ ->
          case System.cmd("sh", ["-c", "stty -g < /dev/tty"], stderr_to_stdout: true) do
            {settings, 0} ->
              System.cmd("sh", ["-c", "stty raw -echo < /dev/tty"], stderr_to_stdout: true)
              String.trim(settings)

            _ ->
              nil
          end
      end

    # Open /dev/tty directly so reads bypass Erlang's buffered stdin port.
    # Without this, IO.binread blocks until the user presses Enter even in raw mode.
    tty_fd =
      case :file.open(~c"/dev/tty", [:read, :binary, :raw]) do
        {:ok, fd} -> fd
        {:error, _} -> nil
      end

    Process.put(:tty_fd, tty_fd)

    try do
      fun.()
    after
      if tty_fd, do: :file.close(tty_fd)
      Process.delete(:tty_fd)
      restore_terminal_mode(original_mode)
    end
  end

  defp restore_terminal_mode(nil), do: :ok

  defp restore_terminal_mode(settings) when is_binary(settings) and settings != "" do
    System.cmd("sh", ["-c", "stty #{settings} < /dev/tty"], stderr_to_stdout: true)
    :ok
  end

  defp restore_terminal_mode(_settings) do
    System.cmd("sh", ["-c", "stty sane < /dev/tty"], stderr_to_stdout: true)
    :ok
  end

  defp read_key do
    case Process.get(:tty_fd) do
      nil ->
        case IO.binread(:stdio, 1) do
          :eof -> "q"
          {:error, _reason} -> "q"
          key when is_binary(key) -> String.downcase(key)
        end

      tty_fd ->
        case :file.read(tty_fd, 1) do
          {:ok, key} -> String.downcase(key)
          :eof -> "q"
          {:error, _reason} -> "q"
        end
    end
  end

  defp selected_employee!(index) do
    Employees.at(index) || raise ArgumentError, "unknown employee index #{index}"
  end

  defp selected_user!(index) do
    Enum.at(@users, index) || raise ArgumentError, "unknown user index #{index}"
  end

  defp random_from(items), do: Enum.at(items, :rand.uniform(length(items)) - 1)

  defp tail_sequence(event_source_id) do
    case Chronicle.get_tail_sequence_number(event_source_id) do
      {:ok, sequence_number} -> sequence_number
      _ -> 0
    end
  end

  defp full_name(%Person{} = person), do: "#{person.first_name} #{person.last_name}"

  defp blank_as(value, fallback) when value in [nil, ""], do: fallback
  defp blank_as(value, _fallback), do: value

  defp format_reason({:constraint_violations, violations}) when is_list(violations) do
    violations
    |> Enum.map(&violation_message/1)
    |> Enum.join("; ")
  end

  defp format_reason({:append_errors, errors}) when is_list(errors) do
    errors
    |> Enum.map(&violation_message/1)
    |> Enum.join("; ")
  end

  defp format_reason(reason), do: inspect(reason)

  defp violation_message(value) when is_binary(value), do: value

  defp violation_message(value) when is_map(value) do
    Map.get(value, :Message) || Map.get(value, :message) || inspect(value)
  end

  defp violation_message(value), do: inspect(value)

  defp format_customer_field(label, value, pii?) do
    display =
      value
      |> to_string()
      |> blank_as("(empty)")

    suffix = if pii?, do: "   [PII]", else: ""
    "  #{String.pad_trailing(label, 15)}: #{display}#{suffix}"
  end
end

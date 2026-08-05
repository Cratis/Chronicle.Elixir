# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule ConsoleSample.Reactors.HrNotificationReactor do
  @moduledoc """
  Reacts to employee lifecycle events by printing console notifications.

  Reactors are Chronicle's "if this then that" mechanism — they observe events
  and produce side effects such as notifications, downstream API calls, or
  follow-up commands. This sample reactor only prints, mirroring the
  equivalent `HrNotificationReactor` in the other Chronicle client samples.
  """

  use Chronicle.Reactors.Reactor

  alias ConsoleSample.Events.{
    EmployeeAddressSet,
    EmployeeEmailSet,
    EmployeeHired,
    EmployeeMoved,
    EmployeePromoted,
    EmployeeWelcomeEmailQueued
  }

  @handles EmployeeHired
  @handles EmployeeAddressSet
  @handles EmployeeEmailSet
  @handles EmployeePromoted
  @handles EmployeeMoved

  @impl true
  def handle(%EmployeeHired{} = event, _context) do
    IO.puts(
      "\n[reactor] Employee hired: #{event.first_name} #{event.last_name} as #{event.title}"
    )

    # Returning {:ok, event_or_events} instead of a plain :ok appends the given
    # event(s) as a side effect of having handled this one — Chronicle appends it
    # right after handle/2 returns, to the same employee's stream since we return a
    # bare event struct (not an EventForEventSourceId targeting a different stream).
    # If the append itself fails, handle/2's overall result becomes {:error, reason},
    # reported the same way a plain {:error, reason} return would be.
    {:ok, %EmployeeWelcomeEmailQueued{template: "welcome-new-hire"}}
  end

  def handle(%EmployeeAddressSet{} = event, _context) do
    IO.puts("\n[reactor] Employee address set to #{event.city}, #{event.country}")
    :ok
  end

  def handle(%EmployeeEmailSet{} = event, _context) do
    IO.puts("\n[reactor] Employee email set to #{event.email}")
    :ok
  end

  def handle(%EmployeePromoted{} = event, _context) do
    IO.puts("\n[reactor] Employee promoted to #{event.new_title}")
    :ok
  end

  def handle(%EmployeeMoved{} = event, _context) do
    IO.puts("\n[reactor] Employee relocated to #{event.city}, #{event.country}")
    :ok
  end
end

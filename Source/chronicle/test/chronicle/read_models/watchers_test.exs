# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.ReadModels.WatchersTest do
  use ExUnit.Case, async: true

  alias Chronicle.ReadModels
  alias Chronicle.ReadModels.Watchers

  defmodule Account do
    use Chronicle.ReadModels.ReadModel
    defstruct id: "", balance: 0
  end

  # Builds a stream_opener that reports every open back to the test process as
  # `{:fake_stream_opened, stream_pid}` and hands control of the fake wire stream to the test
  # through `emit/2` and `stop/1`.
  defp controllable_opener do
    test = self()

    fn _state ->
      stream =
        Stream.resource(
          fn ->
            send(test, {:fake_stream_opened, self()})
            nil
          end,
          fn acc ->
            receive do
              {:emit, item} -> {[item], acc}
              :stop -> {:halt, acc}
            end
          end,
          fn _ -> :ok end
        )

      {:ok, stream}
    end
  end

  defp emit(stream_pid, item), do: send(stream_pid, {:emit, item})
  defp stop(stream_pid), do: send(stream_pid, :stop)

  defp raw_changeset(key, type \\ 0) do
    %{
      ModelKey: key,
      ReadModel: Jason.encode!(%{id: key, balance: 5}),
      Removed: false,
      ChangeType: type,
      EventSequenceNumber: 1
    }
  end

  defp assert_stream_opened do
    assert_receive {:fake_stream_opened, stream_pid}, 1_000
    stream_pid
  end

  defp start_watchers!(client) do
    start_supervised!({Watchers, client: client}, id: client)
  end

  defp subscribe!(opts \\ []) do
    start_watchers!(:watchers_test_client)

    {:ok, watcher} =
      Watchers.subscribe(
        Account,
        Keyword.merge([client: :watchers_test_client, stream_opener: controllable_opener()], opts)
      )

    watcher
  end

  test "a subscriber receives decoded changesets from the shared stream" do
    watcher = subscribe!()
    stream_pid = assert_stream_opened()

    emit(stream_pid, {:ok, raw_changeset("account-1")})

    assert_receive {:chronicle_read_model_changed, Account, changeset}
    assert changeset.model_key == "account-1"
    assert changeset.read_model == %Account{id: "account-1", balance: 5}

    Watchers.unsubscribe(watcher)
  end

  test "two subscribers of the same read model share one stream" do
    start_watchers!(:watchers_test_shared)
    test = self()

    opener = controllable_opener()

    {:ok, watcher1} =
      Watchers.subscribe(Account, client: :watchers_test_shared, stream_opener: opener)

    stream_pid = assert_stream_opened()

    other =
      spawn(fn ->
        {:ok, watcher} = Watchers.subscribe(Account, client: :watchers_test_shared)
        send(test, {:watcher, watcher})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:watcher, watcher2}
    assert watcher1 == watcher2

    # No second stream was opened for the second subscriber.
    refute_receive {:fake_stream_opened, _}, 100

    emit(stream_pid, {:ok, raw_changeset("account-2")})

    assert_receive {:chronicle_read_model_changed, Account, %{model_key: "account-2"}}

    send(other, :stop)
    Watchers.unsubscribe(watcher1)
  end

  test "the stream closes once the last subscriber unsubscribes" do
    watcher = subscribe!()
    stream_pid = assert_stream_opened()

    ref = Process.monitor(stream_pid)
    Watchers.unsubscribe(watcher)

    assert_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}, 1_000
  end

  test "the stream closes once the last subscriber's process exits" do
    start_watchers!(:watchers_test_exit)
    test = self()
    opener = controllable_opener()

    other =
      spawn(fn ->
        {:ok, _watcher} =
          Watchers.subscribe(Account, client: :watchers_test_exit, stream_opener: opener)

        send(test, :subscribed)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :subscribed
    stream_pid = assert_stream_opened()
    ref = Process.monitor(stream_pid)

    send(other, :stop)

    assert_receive {:DOWN, ^ref, :process, ^stream_pid, _reason}, 1_000
  end

  test "a subscriber is told when the shared stream ends and when it resumes" do
    watcher = subscribe!(min_backoff: 1, max_backoff: 5)
    stream_pid = assert_stream_opened()

    emit(stream_pid, {:error, :boom})
    stop(stream_pid)

    assert_receive {:chronicle_read_model_watch_ended, Account, :boom}, 1_000
    assert_receive {:fake_stream_opened, new_stream_pid}, 1_000
    refute new_stream_pid == stream_pid
    assert_receive {:chronicle_read_model_watch_resumed, Account}, 1_000

    Watchers.unsubscribe(watcher)
  end

  test "backoff grows between consecutive reconnect failures" do
    start_watchers!(:watchers_test_backoff)
    test = self()
    counter = :counters.new(1, [])

    # Every attempt fails outright (the opener itself returns an error), so the shared watcher
    # never reaches `:connected` and its backoff keeps growing across attempts.
    failing_opener = fn _state ->
      attempt = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      send(test, {:connect_attempt, attempt, System.monotonic_time(:millisecond)})
      {:error, :boom}
    end

    {:ok, watcher} =
      Watchers.subscribe(Account,
        client: :watchers_test_backoff,
        stream_opener: failing_opener,
        min_backoff: 20,
        max_backoff: 1_000
      )

    assert_receive {:connect_attempt, 0, t0}, 1_000
    assert_receive {:chronicle_read_model_watch_ended, Account, :boom}, 1_000

    assert_receive {:connect_attempt, 1, t1}, 1_000
    assert t1 - t0 >= 15
    assert_receive {:chronicle_read_model_watch_ended, Account, :boom}, 1_000

    assert_receive {:connect_attempt, 2, t2}, 1_000
    assert t2 - t1 >= 35

    Watchers.unsubscribe(watcher)
  end

  describe "ReadModels.subscribe/2 and unsubscribe/1" do
    test "delegate to the shared watcher manager" do
      start_watchers!(:watchers_test_delegation)

      {:ok, watcher} =
        ReadModels.subscribe(Account,
          client: :watchers_test_delegation,
          stream_opener: controllable_opener()
        )

      stream_pid = assert_stream_opened()

      emit(stream_pid, {:ok, raw_changeset("account-3")})
      assert_receive {:chronicle_read_model_changed, Account, %{model_key: "account-3"}}

      assert ReadModels.unsubscribe(watcher) == :ok
    end
  end
end

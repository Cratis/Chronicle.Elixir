# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.Jobs do
  @moduledoc """
  Idiomatic API for working with Chronicle jobs.

  Jobs represent long-running Chronicle operations such as replays and rebuilds.
  This module lets you inspect current jobs, inspect their steps, and control
  their lifecycle.

  ## Usage

      {:ok, jobs} = Chronicle.Jobs.all()
      {:ok, job} = Chronicle.Jobs.get("8a6f5a0c-0fbf-42bd-8db0-a60f9a449b11")
      :ok = Chronicle.Jobs.stop("8a6f5a0c-0fbf-42bd-8db0-a60f9a449b11")

  ## Options

    * `:client` — the client name (default: `Chronicle.Client`)
    * `:namespace` — overrides the client's default namespace
  """

  alias Bcl.Guid, as: BclGuid

  alias Chronicle.Connections.Connection

  alias Chronicle.Jobs.{
    Job,
    JobProgress,
    JobStatusChanged,
    JobStep,
    JobStepProgress,
    JobStepStatusChanged
  }

  alias Cratis.Chronicle.Contracts.Jobs.{
    DeleteJob,
    GetJobRequest,
    GetJobsRequest,
    GetJobStepsRequest,
    Jobs,
    ResumeJob,
    StopJob
  }

  @type job_id :: String.t()

  @doc """
  Stops a job.
  """
  @spec stop(job_id(), keyword()) :: :ok | {:error, term()}
  def stop(job_id, opts \\ []) when is_binary(job_id) do
    perform_job_action(StopJob, :stop, job_id, opts)
  end

  @doc """
  Resumes a stopped job.
  """
  @spec resume(job_id(), keyword()) :: :ok | {:error, term()}
  def resume(job_id, opts \\ []) when is_binary(job_id) do
    perform_job_action(ResumeJob, :resume, job_id, opts)
  end

  @doc """
  Deletes a job.
  """
  @spec delete(job_id(), keyword()) :: :ok | {:error, term()}
  def delete(job_id, opts \\ []) when is_binary(job_id) do
    perform_job_action(DeleteJob, :delete, job_id, opts)
  end

  @doc """
  Gets a single job by identifier.

  Returns `{:ok, nil}` when the job does not exist.
  """
  @spec get(job_id(), keyword()) :: {:ok, Job.t() | nil} | {:error, term()}
  def get(job_id, opts \\ []) when is_binary(job_id) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request = build_job_request(GetJobRequest, config, opts, job_id)

      case Jobs.Stub.get_job(channel, request) do
        {:ok, response} -> {:ok, decode_job_response(response)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Gets all jobs for the configured event store namespace.
  """
  @spec all(keyword()) :: {:ok, [Job.t()]} | {:error, term()}
  def all(opts \\ []) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request =
        struct(GetJobsRequest,
          EventStore: config.event_store,
          Namespace: Keyword.get(opts, :namespace, config.namespace)
        )

      case Jobs.Stub.get_jobs(channel, request) do
        {:ok, response} ->
          jobs =
            response
            |> Map.get(:items, Map.get(response, :Items, []))
            |> Enum.map(&job_from_proto/1)

          {:ok, jobs}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Gets all steps for a specific job.
  """
  @spec steps(job_id(), keyword()) :: {:ok, [JobStep.t()]} | {:error, term()}
  def steps(job_id, opts \\ []) when is_binary(job_id) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request = build_job_request(GetJobStepsRequest, config, opts, job_id)

      case Jobs.Stub.get_job_steps(channel, request) do
        {:ok, response} ->
          steps =
            response
            |> Map.get(:items, Map.get(response, :Items, []))
            |> Enum.map(&job_step_from_proto/1)

          {:ok, steps}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Compatibility alias for `get/2`.
  """
  @spec get_job(job_id(), keyword()) :: {:ok, Job.t() | nil} | {:error, term()}
  def get_job(job_id, opts \\ []), do: get(job_id, opts)

  @doc """
  Compatibility alias for `all/1`.
  """
  @spec get_jobs(keyword()) :: {:ok, [Job.t()]} | {:error, term()}
  def get_jobs(opts \\ []), do: all(opts)

  @doc """
  Compatibility alias for `steps/2`.
  """
  @spec get_job_steps(job_id(), keyword()) :: {:ok, [JobStep.t()]} | {:error, term()}
  def get_job_steps(job_id, opts \\ []), do: steps(job_id, opts)

  defp perform_job_action(request_module, rpc, job_id, opts) do
    with {:ok, channel, config} <- resolve_channel(opts) do
      request = build_job_request(request_module, config, opts, job_id)

      case apply(Jobs.Stub, rpc, [channel, request]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp build_job_request(module, config, opts, job_id) do
    struct(module,
      EventStore: config.event_store,
      Namespace: Keyword.get(opts, :namespace, config.namespace),
      JobId: guid_from_string(job_id)
    )
  end

  defp resolve_channel(opts) do
    client = Keyword.get(opts, :client, Chronicle.Client)

    case Chronicle.Client.config(client) do
      config when is_map(config) ->
        case Connection.channel(config.connection) do
          {:ok, channel} -> {:ok, channel, config}
          error -> error
        end

      _ ->
        {:error, :no_client}
    end
  end

  defp decode_job_response(response) do
    cond do
      job = Map.get(response, :Value0) -> job_from_proto(job)
      job = Map.get(response, :value0) -> job_from_proto(job)
      Map.get(response, :Value1) in [:NotFound, :not_found, 1] -> nil
      Map.get(response, :value1) in [:NotFound, :not_found, 1] -> nil
      true -> nil
    end
  end

  defp job_from_proto(job) do
    %Job{
      id: guid_to_string(Map.get(job, :Id, Map.get(job, :id))),
      details: Map.get(job, :Details, Map.get(job, :details, "")),
      type: Map.get(job, :Type, Map.get(job, :type, "")),
      status: normalize_job_status(Map.get(job, :Status, Map.get(job, :status))),
      created_at: datetime_from_proto(Map.get(job, :Created, Map.get(job, :created))),
      status_changes:
        job
        |> Map.get(:StatusChanges, Map.get(job, :status_changes, []))
        |> Enum.map(&job_status_changed_from_proto/1),
      progress: job_progress_from_proto(Map.get(job, :Progress, Map.get(job, :progress)))
    }
  end

  defp job_progress_from_proto(nil), do: %JobProgress{}

  defp job_progress_from_proto(progress) do
    %JobProgress{
      total_steps: Map.get(progress, :TotalSteps, Map.get(progress, :total_steps, 0)),
      successful_steps:
        Map.get(progress, :SuccessfulSteps, Map.get(progress, :successful_steps, 0)),
      failed_steps: Map.get(progress, :FailedSteps, Map.get(progress, :failed_steps, 0)),
      stopped_steps: Map.get(progress, :StoppedSteps, Map.get(progress, :stopped_steps, 0)),
      completed?: Map.get(progress, :IsCompleted, Map.get(progress, :is_completed, false)),
      stopped?: Map.get(progress, :IsStopped, Map.get(progress, :is_stopped, false)),
      message: Map.get(progress, :Message, Map.get(progress, :message, ""))
    }
  end

  defp job_status_changed_from_proto(status_changed) do
    %JobStatusChanged{
      status:
        normalize_job_status(Map.get(status_changed, :Status, Map.get(status_changed, :status))),
      occurred:
        datetime_from_proto(
          Map.get(status_changed, :Occurred, Map.get(status_changed, :occurred))
        ),
      exception_messages:
        Map.get(
          status_changed,
          :ExceptionMessages,
          Map.get(status_changed, :exception_messages, [])
        ),
      exception_stack_trace:
        Map.get(
          status_changed,
          :ExceptionStackTrace,
          Map.get(status_changed, :exception_stack_trace, "")
        )
    }
  end

  defp job_step_from_proto(step) do
    %JobStep{
      id: guid_to_string(Map.get(step, :Id, Map.get(step, :id))),
      type: Map.get(step, :Type, Map.get(step, :type, "")),
      name: Map.get(step, :Name, Map.get(step, :name, "")),
      status: normalize_job_step_status(Map.get(step, :Status, Map.get(step, :status))),
      status_changes:
        step
        |> Map.get(:StatusChanges, Map.get(step, :status_changes, []))
        |> Enum.map(&job_step_status_changed_from_proto/1),
      progress: job_step_progress_from_proto(Map.get(step, :Progress, Map.get(step, :progress)))
    }
  end

  defp job_step_progress_from_proto(nil), do: %JobStepProgress{}

  defp job_step_progress_from_proto(progress) do
    %JobStepProgress{
      percentage: Map.get(progress, :Percentage, Map.get(progress, :percentage, 0)),
      message: Map.get(progress, :Message, Map.get(progress, :message, ""))
    }
  end

  defp job_step_status_changed_from_proto(status_changed) do
    %JobStepStatusChanged{
      status:
        normalize_job_step_status(
          Map.get(status_changed, :Status, Map.get(status_changed, :status))
        ),
      occurred:
        datetime_from_proto(
          Map.get(status_changed, :Occurred, Map.get(status_changed, :occurred))
        ),
      exception_messages:
        Map.get(
          status_changed,
          :ExceptionMessages,
          Map.get(status_changed, :exception_messages, [])
        ),
      exception_stack_trace:
        Map.get(
          status_changed,
          :ExceptionStackTrace,
          Map.get(status_changed, :exception_stack_trace, "")
        )
    }
  end

  defp normalize_job_status(:PreparingJob), do: :preparing_job
  defp normalize_job_status(:PreparingSteps), do: :preparing_steps
  defp normalize_job_status(:StartingSteps), do: :starting_steps
  defp normalize_job_status(:JOB_STATUS_Running), do: :running
  defp normalize_job_status(:Running), do: :running
  defp normalize_job_status(:JOB_STATUS_CompletedSuccessfully), do: :completed_successfully
  defp normalize_job_status(:CompletedSuccessfully), do: :completed_successfully
  defp normalize_job_status(:CompletedWithFailures), do: :completed_with_failures
  defp normalize_job_status(:JOB_STATUS_Stopped), do: :stopped
  defp normalize_job_status(:Stopped), do: :stopped
  defp normalize_job_status(:JOB_STATUS_Failed), do: :failed
  defp normalize_job_status(:Failed), do: :failed
  defp normalize_job_status(:JOB_STATUS_Removing), do: :removing
  defp normalize_job_status(:Removing), do: :removing
  defp normalize_job_status(1), do: :preparing_job
  defp normalize_job_status(2), do: :preparing_steps
  defp normalize_job_status(3), do: :starting_steps
  defp normalize_job_status(4), do: :running
  defp normalize_job_status(5), do: :completed_successfully
  defp normalize_job_status(6), do: :completed_with_failures
  defp normalize_job_status(7), do: :stopped
  defp normalize_job_status(8), do: :failed
  defp normalize_job_status(9), do: :removing
  defp normalize_job_status(_), do: :none

  defp normalize_job_step_status(:Scheduled), do: :scheduled
  defp normalize_job_step_status(:JOB_STEP_STATUS_Running), do: :running
  defp normalize_job_step_status(:Running), do: :running

  defp normalize_job_step_status(:JOB_STEP_STATUS_CompletedSuccessfully),
    do: :completed_successfully

  defp normalize_job_step_status(:CompletedSuccessfully), do: :completed_successfully
  defp normalize_job_step_status(:CompletedWithFailure), do: :completed_with_failure
  defp normalize_job_step_status(:JOB_STEP_STATUS_Stopped), do: :stopped
  defp normalize_job_step_status(:Stopped), do: :stopped
  defp normalize_job_step_status(:JOB_STEP_STATUS_Failed), do: :failed
  defp normalize_job_step_status(:Failed), do: :failed
  defp normalize_job_step_status(:JOB_STEP_STATUS_Removing), do: :removing
  defp normalize_job_step_status(:Removing), do: :removing
  defp normalize_job_step_status(1), do: :scheduled
  defp normalize_job_step_status(2), do: :running
  defp normalize_job_step_status(3), do: :completed_successfully
  defp normalize_job_step_status(4), do: :completed_with_failure
  defp normalize_job_step_status(5), do: :stopped
  defp normalize_job_step_status(6), do: :failed
  defp normalize_job_step_status(7), do: :removing
  defp normalize_job_step_status(_), do: :unknown

  defp datetime_from_proto(nil), do: nil

  defp datetime_from_proto(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp datetime_from_proto(proto) do
    proto
    |> Map.get(:Value, Map.get(proto, :value))
    |> datetime_from_proto()
  end

  defp guid_from_string(value) do
    guid = struct(BclGuid)

    cond do
      Map.has_key?(guid, :Value) ->
        Map.put(guid, :Value, value)

      Map.has_key?(guid, :value) ->
        Map.put(guid, :value, value)

      Map.has_key?(guid, :lo) and Map.has_key?(guid, :hi) ->
        {lo, hi} = uuid_to_lo_hi(value)
        guid |> Map.put(:lo, lo) |> Map.put(:hi, hi)

      true ->
        guid
    end
  end

  defp guid_to_string(nil), do: ""
  defp guid_to_string(value) when is_binary(value), do: value

  defp guid_to_string(%{Value: value}) when is_binary(value), do: value
  defp guid_to_string(%{value: value}) when is_binary(value), do: value

  defp guid_to_string(%{lo: lo, hi: hi}) when is_integer(lo) and is_integer(hi) do
    <<a::little-32, b::little-16, c::little-16, d::binary-size(2), e::binary-size(6)>> =
      <<lo::little-unsigned-64, hi::little-unsigned-64>>

    [
      Base.encode16(<<a::32>>, case: :lower),
      Base.encode16(<<b::16>>, case: :lower),
      Base.encode16(<<c::16>>, case: :lower),
      Base.encode16(d, case: :lower),
      Base.encode16(e, case: :lower)
    ]
    |> Enum.join("-")
  end

  defp guid_to_string(_), do: ""

  defp uuid_to_lo_hi(value) do
    normalized = String.replace(value, "-", "")

    <<part1::binary-size(8), part2::binary-size(4), part3::binary-size(4), part4::binary-size(4),
      part5::binary-size(12)>> = normalized

    bytes =
      reverse_binary(Base.decode16!(part1, case: :mixed)) <>
        reverse_binary(Base.decode16!(part2, case: :mixed)) <>
        reverse_binary(Base.decode16!(part3, case: :mixed)) <>
        Base.decode16!(part4 <> part5, case: :mixed)

    <<lo::little-unsigned-64, hi::little-unsigned-64>> = bytes
    {lo, hi}
  end

  defp reverse_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reverse()
    |> :erlang.list_to_binary()
  end
end

# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Chronicle.EventSequences.AppendRejectionsTest do
  use Chronicle.AppendWireCase, async: false

  alias Chronicle.EventSequences.AppendResponse

  for path <- [:single, :ordinary, :rich, :transaction] do
    test "#{path} rejects a concurrency violation even with success true", %{opts: opts} do
      violation = %Wire.ConcurrencyViolation{
        EventSourceId: "source",
        ExpectedSequenceNumber: 3,
        ActualSequenceNumber: 4
      }

      key = if unquote(path) == :single, do: :ConcurrencyViolation, else: :ConcurrencyViolations
      value = if unquote(path) == :single, do: violation, else: [violation]
      put_response(:append_payload, [{:IsSuccess, true}, {key, value}])
      assert {:error, {:concurrency_violations, [^violation]}} = append(unquote(path), opts)
    end

    for {flag, reason} <- [
          HasConcurrencyViolations: :concurrency_violations,
          HasConstraintViolations: :constraint_violations,
          HasErrors: :append_errors
        ] do
      test "#{path} rejects #{flag} even without details", %{opts: opts} do
        put_response(:append_payload, [{:IsSuccess, true}, {unquote(flag), true}])
        assert {:error, {unquote(reason), []}} = append(unquote(path), opts)
      end
    end

    test "#{path} rejects constraint details even without flag", %{opts: opts} do
      violation = %Wire.ConstraintViolation{ConstraintName: "unique"}
      put_response(:append_payload, IsSuccess: true, ConstraintViolations: [violation])
      assert {:error, {:constraint_violations, [^violation]}} = append(unquote(path), opts)
    end

    test "#{path} rejects error details even without flag", %{opts: opts} do
      put_response(:append_payload, IsSuccess: true, Errors: ["rejected"])
      assert {:error, {:append_errors, ["rejected"]}} = append(unquote(path), opts)
    end

    test "#{path} rejects a false success flag", %{opts: opts} do
      put_response(:append_payload, IsSuccess: false)
      assert {:error, {:append_rejected, _}} = append(unquote(path), opts)
    end

    test "#{path} rejects missing response payload", %{opts: opts} do
      put_response(:envelope, Response: nil)
      assert {:error, {:invalid_append_response, nil}} = append(unquote(path), opts)
    end

    test "#{path} rejects envelope validation results before reading success payload", %{
      opts: opts
    } do
      validation = %Wire.ValidationResult{Message: "invalid"}
      put_response(:envelope, ValidationResults: [validation])
      assert {:error, {:validation_results, [^validation]}} = append(unquote(path), opts)
    end

    test "#{path} retains authorization and exception failures", %{opts: opts} do
      put_response(:envelope, IsAuthorized: false, AuthorizationFailureReason: "denied")
      assert {:error, {:unauthorized, "denied"}} = append(unquote(path), opts)
      put_response(:envelope, ExceptionMessages: ["failure"])
      assert {:error, {:exception, ["failure"]}} = append(unquote(path), opts)
    end
  end

  test "unknown and malformed response shapes never become success" do
    for response <- [
          nil,
          :unknown,
          %{},
          %{IsSuccess: true, ConcurrencyViolations: nil},
          %{IsSuccess: nil},
          %{SequenceNumbers: [1]}
        ] do
      assert {:error, _} = AppendResponse.normalize(response)
    end
  end

  test "transaction rejection marks the unit unsuccessful", %{opts: opts} do
    put_response(:append_payload, IsSuccess: false, HasConcurrencyViolations: true)
    unit = UnitOfWork.begin()
    assert :ok = EventLog.append("source", %Event{}, opts)
    assert {:error, {:concurrency_violations, []}} = UnitOfWork.commit(unit)
    assert UnitOfWork.is_completed?(unit)
    refute UnitOfWork.is_success?(unit)
  end
end

```elixir
defmodule MyApp.SubscribeEndpoint do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.{CourseSubscriptionSeatTaken, CourseSubscriptionStudentJoinedCourse}
  alias MyApp.ReadModels.{CourseSeats, StudentCourses}

  # Returns the HTTP outcome for POST /courses/:course_id/students/:student_id.
  def handle(course_id, student_id) do
    # decide/2 commits as soon as the function returns, while the response can still change.
    result =
      Chronicle.decide(fn _unit_of_work ->
        # get/2 enrolls each read in the unit of work.
        {:ok, course} = DecisionReads.get(CourseSeats, course_id)
        {:ok, student} = DecisionReads.get(StudentCourses, student_id)
        student_courses = if student.instance, do: student.instance.subscribed, else: 0

        cond do
          course.instance == nil ->
            :not_found

          course.instance.subscribed >= course.instance.capacity or student_courses >= 5 ->
            :unprocessable_entity

          true ->
            # Inside decide/2 an append is staged in the unit of work, guarded by the decision reads.
            :ok = EventLog.append(course_id, %CourseSubscriptionSeatTaken{student_id: student_id})

            :ok =
              EventLog.append(student_id, %CourseSubscriptionStudentJoinedCourse{course_id: course_id})

            :no_content
        end
      end)

    case result do
      {:ok, response} -> response
      {:error, %DecisionConflict{}} -> :conflict
      {:error, _reason} -> :unprocessable_entity
    end
  end
end
```

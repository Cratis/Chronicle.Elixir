```elixir
defmodule MyApp.Events.CourseSubscriptionCourseDefined do
  use Chronicle.Events.EventType, id: "course-subscription-course-defined"

  defstruct [:name, :capacity]
end

defmodule MyApp.Events.CourseSubscriptionCourseCapacityChanged do
  use Chronicle.Events.EventType, id: "course-subscription-course-capacity-changed"

  defstruct [:capacity]
end

# Events of the course's own story.
defmodule MyApp.Events.CourseSubscriptionSeatTaken do
  use Chronicle.Events.EventType, id: "course-subscription-seat-taken"

  defstruct [:student_id]
end

defmodule MyApp.Events.CourseSubscriptionSeatReleased do
  use Chronicle.Events.EventType, id: "course-subscription-seat-released"

  defstruct [:student_id]
end

# Events of the student's own story.
defmodule MyApp.Events.CourseSubscriptionStudentJoinedCourse do
  use Chronicle.Events.EventType, id: "course-subscription-student-joined-course"

  defstruct [:course_id]
end

defmodule MyApp.Events.CourseSubscriptionStudentLeftCourse do
  use Chronicle.Events.EventType, id: "course-subscription-student-left-course"

  defstruct [:course_id]
end

defmodule MyApp.ReadModels.CourseSeats do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, capacity: 0, subscribed: 0

  from MyApp.Events.CourseSubscriptionCourseDefined, set: [id: :event_source_id, capacity: :capacity]
  from MyApp.Events.CourseSubscriptionCourseCapacityChanged, set: [capacity: :capacity]
  from MyApp.Events.CourseSubscriptionSeatTaken, add: [subscribed: 1]
  from MyApp.Events.CourseSubscriptionSeatReleased, subtract: [subscribed: 1]
end

defmodule MyApp.ReadModels.StudentCourses do
  use Chronicle.ReadModels.ReadModel

  defstruct id: nil, subscribed: 0

  from MyApp.Events.CourseSubscriptionStudentJoinedCourse,
    set: [id: :event_source_id],
    add: [subscribed: 1]

  from MyApp.Events.CourseSubscriptionStudentLeftCourse, subtract: [subscribed: 1]
end

defmodule MyApp.CourseSubscriptionSubscribeStudent do
  alias Chronicle.EventSequences.EventLog
  alias Chronicle.ReadModels.{DecisionConflict, DecisionReads}
  alias MyApp.Events.{CourseSubscriptionSeatTaken, CourseSubscriptionStudentJoinedCourse}
  alias MyApp.ReadModels.{CourseSeats, StudentCourses}

  @max_courses_per_student 5

  def handle(course_id, student_id) do
    result =
      Chronicle.decide(fn _unit_of_work ->
        # One decision read per event source: the commit guards both.
        {:ok, course} = DecisionReads.get(CourseSeats, course_id)
        {:ok, student} = DecisionReads.get(StudentCourses, student_id)
        student_courses = if student.instance, do: student.instance.subscribed, else: 0

        cond do
          course.instance == nil ->
            :unknown_course

          course.instance.subscribed >= course.instance.capacity ->
            :course_is_full

          student_courses >= @max_courses_per_student ->
            :student_has_too_many_courses

          true ->
            # One fact, two event sources, two event types: each read model counts only the
            # types of its own source.
            :ok = EventLog.append(course_id, %CourseSubscriptionSeatTaken{student_id: student_id})

            :ok =
              EventLog.append(student_id, %CourseSubscriptionStudentJoinedCourse{course_id: course_id})

            :subscribed
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      # Either side changed after it was read. Nothing was appended for either source.
      {:error, %DecisionConflict{}} -> :changed_concurrently
      {:error, _reason} -> :failed
    end
  end
end
```

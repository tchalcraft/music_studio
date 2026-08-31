defmodule MusicStudio.AnalyticsTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.Analytics
  alias MusicStudio.Analytics.Event

  test "record_event/1 requires a verb and subject_type and defaults occurred_at" do
    assert {:error, changeset} = Analytics.record_event(%{})
    errs = errors_on(changeset)
    assert "can't be blank" in errs.verb
    assert "can't be blank" in errs.subject_type

    assert {:ok, %Event{} = event} =
             Analytics.record_event(%{verb: "lead.created", subject_type: "lead", subject_id: 42})

    assert event.subject_id == "42"
    assert event.occurred_at
  end

  test "list_events_for/2 returns events about a subject, newest first" do
    {:ok, _} =
      Analytics.record_event(%{
        verb: "lesson.scheduled",
        subject_type: "lesson",
        subject_id: "abc"
      })

    {:ok, _} =
      Analytics.record_event(%{
        verb: "lesson.completed",
        subject_type: "lesson",
        subject_id: "abc"
      })

    events = Analytics.list_events_for("lesson", "abc")
    assert length(events) == 2
    assert hd(events).verb == "lesson.completed"
  end

  test "reporting views return rows as maps (empty is fine)" do
    assert is_list(Analytics.lesson_facts())
    assert is_list(Analytics.funnel())
  end
end

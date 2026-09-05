defmodule MusicStudio.Scheduling.NotifierTest do
  use ExUnit.Case, async: true
  import Swoosh.TestAssertions

  alias MusicStudio.Scheduling.Notifier

  defp details do
    %{
      visitor_name: "Sam",
      visitor_email: "sam@example.com",
      instrument: "piano",
      starts_at: DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC"),
      ends_at: DateTime.new!(~D[2026-09-10], ~T[23:00:00], "Etc/UTC"),
      duration_minutes: 60,
      manage_url: "http://localhost:4000/book/manage/tok",
      uid: "uid-1",
      organizer_email: "tristan@example.com",
      organizer_name: "Tristan Chalcraft",
      timezone: "America/Vancouver"
    }
  end

  test "visitor confirmation is multipart (html + text) with the wordmark, the time and an .ics" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.to == [{"Sam", "sam@example.com"}] and
        is_binary(email.html_body) and email.html_body =~ "Tristan" and
        is_binary(email.text_body) and
        Enum.any?(email.attachments, &(&1.content_type == "text/calendar"))
    end)
  end

  test "plaintext confirmation includes manage your booking link" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.to == [{"Sam", "sam@example.com"}] and
        email.text_body =~ "Manage your booking" and email.text_body =~ "tok"
    end)
  end

  test "cancellation email is sent to the visitor" do
    assert {:ok, _} = Notifier.deliver_cancellation(details())
    assert_email_sent(fn e -> e.to == [{"Sam", "sam@example.com"}] and e.subject =~ "cancel" end)
  end

  test "reschedule email is sent to the visitor" do
    assert {:ok, _} = Notifier.deliver_reschedule(details())
    assert_email_sent(fn e -> e.to == [{"Sam", "sam@example.com"}] and e.subject =~ "moved" end)
  end
end

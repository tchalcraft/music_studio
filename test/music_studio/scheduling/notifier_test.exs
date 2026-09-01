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
      timezone: "America/Vancouver"
    }
  end

  test "sends a visitor confirmation carrying a text/calendar attachment" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.to == [{"Sam", "sam@example.com"}] and
        Enum.any?(email.attachments, &(&1.content_type == "text/calendar"))
    end)
  end
end

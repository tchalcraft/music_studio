defmodule MusicStudio.Scheduling.ICSTest do
  use ExUnit.Case, async: true

  alias MusicStudio.Scheduling.ICS

  defp attrs do
    %{
      uid: "abc-123",
      summary: "Piano lesson — Sam",
      description: "60-minute piano lesson",
      location: "Studio",
      starts_at: DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC"),
      ends_at: DateTime.new!(~D[2026-09-10], ~T[23:00:00], "Etc/UTC"),
      organizer_email: "tristan@example.com",
      organizer_name: "Tristan Chalcraft",
      attendee_email: "sam@example.com",
      now: DateTime.new!(~D[2026-09-01], ~T[12:00:00], "Etc/UTC")
    }
  end

  test "builds a VEVENT with UTC stamps and the right UID" do
    ics = ICS.build(attrs())
    assert ics =~ "BEGIN:VCALENDAR"
    assert ics =~ "BEGIN:VEVENT"
    assert ics =~ "UID:abc-123"
    assert ics =~ "DTSTART:20260910T220000Z"
    assert ics =~ "DTEND:20260910T230000Z"
    assert ics =~ "ORGANIZER;CN=\"Tristan Chalcraft\":mailto:tristan@example.com"
    assert ics =~ "ATTENDEE;RSVP=TRUE:mailto:sam@example.com"
    assert String.ends_with?(ics, "END:VCALENDAR\r\n")
  end

  test "escapes special characters in text fields" do
    ics = ICS.build(%{attrs() | summary: "Lesson; with, chars"})
    assert ics =~ "SUMMARY:Lesson\\; with\\, chars"
  end

  test "organizer line includes CN parameter with display name when present" do
    ics = ICS.build(attrs())
    assert ics =~ "ORGANIZER;CN=\"Tristan Chalcraft\":mailto:tristan@example.com"
  end

  test "organizer line has no CN when organizer_name is nil" do
    ics = ICS.build(%{attrs() | organizer_name: nil})
    assert ics =~ "ORGANIZER:mailto:tristan@example.com"
    refute ics =~ "CN="
  end

  test "organizer line has no CN when organizer_name is empty string" do
    ics = ICS.build(%{attrs() | organizer_name: ""})
    assert ics =~ "ORGANIZER:mailto:tristan@example.com"
    refute ics =~ "CN="
  end

  test "escapes quotes and backslashes in organizer CN parameter" do
    ics = ICS.build(%{attrs() | organizer_name: ~s(Tristan "T" Chalcraft)})
    assert ics =~ "ORGANIZER;CN=\"Tristan \\\"T\\\" Chalcraft\":mailto:tristan@example.com"
  end
end

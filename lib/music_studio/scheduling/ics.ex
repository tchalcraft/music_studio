defmodule MusicStudio.Scheduling.ICS do
  @moduledoc """
  Builds a minimal, valid iCalendar (`.ics`) VEVENT for a booked lesson, attached to the
  Resend confirmation so the student can add it to their own calendar. Times are emitted
  as UTC (`...Z`). Hand-rolled — no dependency needed for a single VEVENT.
  """

  @spec build(map()) :: binary()
  def build(a) do
    [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Music Studio//Booking//EN",
      "CALSCALE:GREGORIAN",
      "METHOD:REQUEST",
      "BEGIN:VEVENT",
      "UID:#{a.uid}",
      "DTSTAMP:#{stamp(a.now)}",
      "DTSTART:#{stamp(a.starts_at)}",
      "DTEND:#{stamp(a.ends_at)}",
      "SUMMARY:#{escape(a.summary)}",
      "DESCRIPTION:#{escape(a.description)}",
      "LOCATION:#{escape(a.location)}",
      "ORGANIZER:mailto:#{a.organizer_email}",
      "ATTENDEE;RSVP=TRUE:mailto:#{a.attendee_email}",
      "STATUS:CONFIRMED",
      "END:VEVENT",
      "END:VCALENDAR"
    ]
    |> Enum.map(&(&1 <> "\r\n"))
    |> IO.iodata_to_binary()
  end

  defp stamp(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  # RFC 5545 text escaping: backslash, semicolon, comma, newline.
  defp escape(text) do
    text
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace("\n", "\\n")
  end
end

defmodule MusicStudio.Scheduling.Notifier do
  @moduledoc """
  Sends booking emails via the configured Swoosh adapter (Resend in prod): a confirmation
  to the student with an `.ics` attachment, and a notification to the teacher. Addresses
  come from `config :music_studio, MusicStudio.Scheduling` — never hard-coded.
  """
  import Swoosh.Email

  alias MusicStudio.Mailer
  alias MusicStudio.Scheduling.ICS

  @spec deliver_booking_emails(map()) :: {:ok, map()} | {:error, term()}
  def deliver_booking_emails(details) do
    from_addr = cfg(:notify_from)
    to_addr = cfg(:notify_to)
    when_str = local_string(details.starts_at, details.timezone)

    ics = ICS.build(ics_attrs(details, from_addr))

    confirmation =
      new()
      |> to({details.visitor_name, details.visitor_email})
      |> from({"Music Studio", from_addr})
      |> subject("Your #{details.instrument} lesson is booked — #{when_str}")
      |> text_body(confirmation_body(details, when_str))
      |> attachment(
        Swoosh.Attachment.new({:data, ics},
          filename: "lesson.ics",
          content_type: "text/calendar",
          type: :attachment
        )
      )

    notification =
      new()
      |> to(to_addr)
      |> from({"Music Studio Website", from_addr})
      |> reply_to(details.visitor_email)
      |> subject("New booking: #{details.instrument} — #{when_str}")
      |> text_body(notification_body(details, when_str))

    with {:ok, _} <- Mailer.deliver(confirmation),
         {:ok, _} <- Mailer.deliver(notification) do
      {:ok, %{confirmation: confirmation, notification: notification}}
    end
  end

  defp ics_attrs(d, organizer_email) do
    %{
      uid: d.uid,
      summary: "#{String.capitalize(d.instrument)} lesson — #{d.visitor_name}",
      description: "#{d.duration_minutes}-minute #{d.instrument} lesson. Manage: #{d.manage_url}",
      location: "Studio",
      starts_at: d.starts_at,
      ends_at: d.ends_at,
      organizer_email: d.organizer_email || organizer_email,
      attendee_email: d.visitor_email,
      now: DateTime.utc_now()
    }
  end

  defp confirmation_body(d, when_str) do
    """
    Hi #{d.visitor_name},

    Your #{d.duration_minutes}-minute #{d.instrument} lesson is booked for #{when_str}.
    The attached calendar file (lesson.ics) can be added to your own calendar.

    Need to change it? #{d.manage_url}

    See you then!
    """
  end

  defp notification_body(d, when_str) do
    """
    New online booking:

    Name:       #{d.visitor_name}
    Email:      #{d.visitor_email}
    Instrument: #{String.capitalize(d.instrument)}
    When:       #{when_str} (#{d.duration_minutes} min)
    """
  end

  defp local_string(dt, tz) do
    dt |> DateTime.shift_zone!(tz) |> Calendar.strftime("%A %B %-d, %Y at %-I:%M %p %Z")
  end

  defp cfg(key),
    do: Keyword.fetch!(Application.get_env(:music_studio, MusicStudio.Scheduling), key)
end

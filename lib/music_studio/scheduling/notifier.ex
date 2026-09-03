defmodule MusicStudio.Scheduling.Notifier do
  @moduledoc """
  Sends booking emails via the configured Swoosh adapter (Resend in prod). Visitor-facing
  emails (confirmation, cancellation, reschedule) are branded multipart HTML+text via
  `EmailTemplate`, with an `.ics` attachment on the confirmation. The studio notification
  stays plain text. Addresses come from `config :music_studio, MusicStudio.Scheduling`.
  """
  import Swoosh.Email

  alias MusicStudio.Mailer
  alias MusicStudio.Scheduling.{EmailTemplate, ICS}

  @spec deliver_booking_emails(map()) :: {:ok, map()} | {:error, term()}
  def deliver_booking_emails(details) do
    from_addr = cfg(:notify_from)
    to_addr = cfg(:notify_to)
    when_str = local_string(details.starts_at, details.timezone)
    ics = ICS.build(ics_attrs(details, from_addr))

    gcal =
      EmailTemplate.google_calendar_url(%{
        title: "#{String.capitalize(details.instrument)} lesson",
        details:
          "#{details.duration_minutes}-minute #{details.instrument} lesson. Manage: #{details.manage_url}",
        location: "Studio",
        starts_at: details.starts_at,
        ends_at: details.ends_at
      })

    body_opts = [
      title: "You're booked!",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: [
        "Your #{details.duration_minutes}-minute #{details.instrument} lesson is confirmed. The attached calendar file (lesson.ics) can be added to your calendar, or use the button below for Google Calendar.",
        "Need to change it? Use the link below."
      ],
      details: [{"When", when_str}, {"Where", "Studio"}],
      cta: %{label: "Add to Google Calendar", url: gcal}
    ]

    extra = [{"Manage your booking", details.manage_url}]

    confirmation =
      new()
      |> to({details.visitor_name, details.visitor_email})
      |> from({"Tristan Music", from_addr})
      |> subject("Your #{details.instrument} lesson is booked — #{when_str}")
      |> html_body(EmailTemplate.html(body_opts))
      |> text_body(EmailTemplate.text(body_opts ++ [details: body_opts[:details] ++ extra]))
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

  @spec deliver_cancellation(map()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_cancellation(details) do
    when_str = local_string(details.starts_at, details.timezone)

    opts = [
      title: "Your lesson is cancelled",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: [
        "Your #{details.instrument} lesson on #{when_str} has been cancelled. Hope to see you again soon — you can book any time."
      ],
      details: [{"Was", when_str}],
      cta: nil
    ]

    deliver_visitor(details, "Your #{details.instrument} lesson was cancelled", opts)
  end

  @spec deliver_reschedule(map()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reschedule(details) do
    when_str = local_string(details.starts_at, details.timezone)

    opts = [
      title: "Your lesson moved",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: ["Your #{details.instrument} lesson has been moved. Here are the new details:"],
      details: [{"New time", when_str}, {"Where", "Studio"}],
      cta: %{label: "Manage your booking", url: details.manage_url}
    ]

    deliver_visitor(details, "Your #{details.instrument} lesson moved to #{when_str}", opts)
  end

  @spec deliver_series_emails(map()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_series_emails(details) do
    cadence = if details.interval_weeks == 2, do: "bi-weekly", else: "weekly"

    opts = [
      title: "Your lessons are booked!",
      greeting: "Hi #{details.visitor_name},",
      paragraphs: series_paragraphs(details, cadence),
      details: series_detail_rows(details),
      cta: %{label: "Manage your series", url: details.manage_url}
    ]

    email =
      new()
      |> to({details.visitor_name, details.visitor_email})
      |> from({"Tristan Music", cfg(:notify_from)})
      |> subject("Your #{details.instrument} lessons are booked")
      |> html_body(EmailTemplate.html(opts))
      |> text_body(EmailTemplate.text(opts))

    with {:ok, _} <- Mailer.deliver(email), do: {:ok, email}
  end

  defp series_paragraphs(details, cadence) do
    count = length(details.lesson_starts)

    base = [
      "Your #{cadence} #{details.instrument} lessons are booked — #{count} lessons through the school year (ends June 30)."
    ]

    case length(details.conflicted) do
      0 ->
        base

      n ->
        base ++
          [
            "#{n} week(s) couldn't be booked at your usual time — pick another time for those from the manage page."
          ]
    end
  end

  defp series_detail_rows(%{lesson_starts: []}), do: [{"Lessons", "0"}]

  defp series_detail_rows(%{lesson_starts: [first | _] = starts} = details) do
    [
      {"First lesson", local_string(first, details.timezone)},
      {"Last lesson", local_string(List.last(starts), details.timezone)},
      {"Lessons", "#{length(starts)}"}
    ]
  end

  defp deliver_visitor(details, subject, opts) do
    email =
      new()
      |> to({details.visitor_name, details.visitor_email})
      |> from({"Tristan Music", cfg(:notify_from)})
      |> subject(subject)
      |> html_body(EmailTemplate.html(opts))
      |> text_body(EmailTemplate.text(opts))

    with {:ok, _} <- Mailer.deliver(email), do: {:ok, email}
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

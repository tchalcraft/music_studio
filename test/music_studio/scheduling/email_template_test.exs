defmodule MusicStudio.Scheduling.EmailTemplateTest do
  use ExUnit.Case, async: false

  alias MusicStudio.Scheduling.EmailTemplate

  setup do
    prev = Application.get_env(:music_studio, MusicStudio.Scheduling)
    on_exit(fn -> Application.put_env(:music_studio, MusicStudio.Scheduling, prev) end)

    Application.put_env(
      :music_studio,
      MusicStudio.Scheduling,
      Keyword.merge(prev,
        website_url: "https://studio.example",
        social: [instagram: "https://instagram.com/tristan", facebook: nil, youtube: nil]
      )
    )
  end

  defp opts do
    [
      title: "You're booked!",
      greeting: "Hi Sam,",
      paragraphs: ["Your 60-minute piano lesson is confirmed."],
      details: [{"When", "Thursday September 10, 4:00 PM PDT"}, {"Where", "Studio"}],
      cta: %{label: "Manage your booking", url: "https://studio.example/book/manage/tok"}
    ]
  end

  test "html carries the wordmark, title, details, CTA and only configured links" do
    html = EmailTemplate.html(opts())
    assert html =~ "Tristan"
    assert html =~ "You&#39;re booked!" or html =~ "You're booked!"
    assert html =~ "Thursday September 10, 4:00 PM PDT"
    assert html =~ "Manage your booking"
    assert html =~ "https://studio.example/book/manage/tok"
    assert html =~ "https://instagram.com/tristan"
    refute html =~ "facebook.com"
    refute html =~ "youtube.com"
    # inlined styles, no external stylesheet
    assert html =~ "style="
    refute html =~ "<link"
  end

  test "text renderer produces a plain-text counterpart" do
    text = EmailTemplate.text(opts())
    assert text =~ "Hi Sam,"
    assert text =~ "When: Thursday September 10, 4:00 PM PDT"
    assert text =~ "Manage your booking: https://studio.example/book/manage/tok"
  end

  test "google_calendar_url builds a TEMPLATE render URL with UTC stamps" do
    url =
      EmailTemplate.google_calendar_url(%{
        title: "Piano lesson",
        details: "See you then",
        location: "Studio",
        starts_at: DateTime.new!(~D[2026-09-10], ~T[22:00:00], "Etc/UTC"),
        ends_at: DateTime.new!(~D[2026-09-10], ~T[23:00:00], "Etc/UTC")
      })

    assert url =~ "https://calendar.google.com/calendar/render?action=TEMPLATE"
    assert url =~ "dates=20260910T220000Z%2F20260910T230000Z"
    assert url =~ "text=Piano+lesson" or url =~ "text=Piano%20lesson"
  end
end

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
      organizer_email: "tchalcraftmusic@gmail.com",
      organizer_name: "Tristan Chalcraft Music",
      studio_address: "14826 Thrift Avenue, White Rock, BC, Canada",
      timezone: "America/Vancouver"
    }
  end

  defp calendar_attachment(email) do
    Enum.find(email.attachments, &(&1.content_type == "text/calendar"))
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

  # Regression for #6: the manage-booking URL must survive into the PLAINTEXT body.
  test "plaintext confirmation includes the manage-booking URL" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.to == [{"Sam", "sam@example.com"}] and
        email.text_body =~ "http://localhost:4000/book/manage/tok"
    end)
  end

  # #15: the confirmation gets a primary "Modify booking" button + a secondary
  # "Add to Google Calendar" link.
  test "confirmation has a Modify booking button and an Add to Google Calendar link" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.html_body =~ "Modify booking" and
        email.html_body =~ "/book/manage/tok" and
        email.html_body =~ "Add to Google Calendar"
    end)
  end

  # #15: the real studio address appears in the email and the .ics LOCATION (not "Studio").
  test "confirmation and .ics carry the real studio address" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      email.html_body =~ "14826 Thrift Avenue" and
        calendar_attachment(email).data =~ "14826 Thrift Avenue"
    end)
  end

  # #11: the .ics organizer presents as the studio name + real (Gmail) address.
  test "the .ics organizer is the studio identity, not a placeholder" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      ics = calendar_attachment(email).data

      ics =~ "ORGANIZER;CN=\"Tristan Chalcraft Music\":mailto:tchalcraftmusic@gmail.com" and
        not (ics =~ "tristan@example.com")
    end)
  end

  # #15: a single booking's .ics reads as a one-off lesson (no student name, no series marker).
  test "single-booking .ics SUMMARY is a plain lesson title" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())

    assert_email_sent(fn email ->
      calendar_attachment(email).data =~ "SUMMARY:Piano lesson\r\n"
    end)
  end

  # #11: replies/RSVPs go to the organizer inbox.
  test "confirmation Reply-To is the organizer email" do
    assert {:ok, _} = Notifier.deliver_booking_emails(details())
    assert_email_sent(fn email -> email.reply_to == {"", "tchalcraftmusic@gmail.com"} end)
  end

  test "cancellation email is sent to the visitor" do
    assert {:ok, _} = Notifier.deliver_cancellation(details())
    assert_email_sent(fn e -> e.to == [{"Sam", "sam@example.com"}] and e.subject =~ "cancel" end)
  end

  test "reschedule email is sent to the visitor with the new time and address" do
    assert {:ok, _} = Notifier.deliver_reschedule(details())

    assert_email_sent(fn e ->
      e.to == [{"Sam", "sam@example.com"}] and e.subject =~ "moved" and
        e.html_body =~ "14826 Thrift Avenue"
    end)
  end
end

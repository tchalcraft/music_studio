defmodule MusicStudioWeb.BookingLiveRecurringTest do
  use MusicStudioWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias MusicStudio.Catalog
  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    {:ok, _} = Catalog.create_teacher(%{name: "Tristan", email: "t@example.com", active: true})
    {:ok, _} = Catalog.create_instrument(%{name: "Piano", slug: "piano", active: true})

    {:ok, _} =
      Catalog.create_offering(%{
        name: "60",
        duration_minutes: 60,
        price_cents: 7000,
        active: true
      })

    {:ok, _} =
      Credentials.upsert(%{
        provider: "google",
        refresh_token: "rt",
        access_token: "at",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        availability_calendar_id: "c",
        target_calendar_id: "c"
      })

    Req.Test.stub(GoogleAuth, fn conn ->
      case conn.method do
        "GET" ->
          conn = Plug.Conn.fetch_query_params(conn)
          day = conn.query_params["timeMin"] |> String.slice(0, 10)

          Req.Test.json(conn, %{
            "items" => [
              %{
                "start" => %{"dateTime" => day <> "T15:00:00-07:00"},
                "end" => %{"dateTime" => day <> "T18:00:00-07:00"}
              }
            ]
          })

        _ ->
          Req.Test.json(conn, %{"id" => "evt-1"})
      end
    end)

    :ok
  end

  # A concrete future slot (June term, well past the 24h min-notice). Its day gets a
  # 15:00–18:00 block from the stub, so 16:00 is a bookable slot.
  defp future_slot_iso do
    ~D[2027-06-01]
    |> MusicStudio.Scheduling.Recurrence.occurrence_utc(~T[16:00:00], "America/Vancouver")
    |> DateTime.to_iso8601()
  end

  test "choosing weekly + a slot shows a series preview", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")

    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    assert render(view) =~ "Available times"
    render_change(view, "set_cadence", %{"cadence" => "weekly"})

    html = render_click(view, "pick_slot", %{"start" => future_slot_iso()})
    assert html =~ "lessons through June 30"
  end

  test "booking a weekly series shows the series confirmation", %{conn: conn} do
    {:ok, view, _} = live(conn, "/book")

    render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})
    render_change(view, "set_cadence", %{"cadence" => "weekly"})
    render_click(view, "pick_slot", %{"start" => future_slot_iso()})

    html =
      render_submit(view, "book", %{
        "booking" => %{"name" => "Sam Lee", "email" => "sam@example.com", "phone" => ""}
      })

    assert html =~ "Your series is booked"
    assert html =~ "lessons through June 30"
  end
end

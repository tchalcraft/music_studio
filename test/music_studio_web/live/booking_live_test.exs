defmodule MusicStudioWeb.BookingLiveTest do
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

    :ok
  end

  test "renders the instrument + duration picker", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/book")
    assert html =~ "Book a lesson"
    assert html =~ "Piano"
  end

  test "shows slots for a picked instrument + duration", %{conn: conn} do
    Req.Test.stub(GoogleAuth, fn conn ->
      Req.Test.json(conn, %{
        "items" => [
          %{
            "start" => %{"dateTime" => "2027-01-05T15:00:00-08:00"},
            "end" => %{"dateTime" => "2027-01-05T17:00:00-08:00"}
          }
        ]
      })
    end)

    {:ok, view, _} = live(conn, "/book")

    html =
      render_change(view, "choose", %{"instrument_slug" => "piano", "duration_minutes" => "60"})

    assert html =~ "Available times"
  end
end

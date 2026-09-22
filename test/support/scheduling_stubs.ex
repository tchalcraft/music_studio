defmodule MusicStudio.SchedulingStubs do
  @moduledoc """
  Test helpers for the Scheduling context's Google integration: configure a throwaway
  service-account key + calendar ids, and route the HTTP client at a `Req.Test` stub whose
  token endpoint is handled automatically (callers only describe calendar GET/POST).
  """
  import ExUnit.Callbacks

  alias MusicStudio.Scheduling.GoogleAuth
  alias MusicStudio.Scheduling.Recurrence

  @doc """
  A Tuesday early in the *upcoming* school year — always in the future (whatever the wall
  clock says) with a full ~40-week runway to the following June 30, and always in PDT
  (September), so tests stay deterministic without hard-coded calendar dates.
  """
  def early_series_start do
    today = Date.utc_today()
    year = if today.month >= 9, do: today.year + 1, else: today.year
    first_tuesday(Date.new!(year, 9, 1))
  end

  @doc """
  A Tuesday positioned so a weekly series yields exactly four lessons through the school-year
  term end (the last four Tuesdays on/before June 30 of `early_series_start/0`'s year).
  """
  def late_series_start do
    term_end = Recurrence.term_end(early_series_start())
    last_tuesday = Date.add(term_end, -rem(Date.day_of_week(term_end) - 2 + 7, 7))
    Date.add(last_tuesday, -21)
  end

  # First Tuesday on/after the given date (Monday = 1 … Tuesday = 2).
  defp first_tuesday(date), do: Date.add(date, rem(2 - Date.day_of_week(date) + 7, 7))

  @doc """
  Put a throwaway service-account key + calendar ids (`availability`/`target` = "c") in
  config for this test, restoring on exit. Extra config can be merged via `opts`.
  """
  def service_account_config(opts \\ []) do
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa)])
    prev = Application.get_env(:music_studio, MusicStudio.Scheduling)

    base = [
      service_account_key: %{
        "client_email" => "svc@proj.iam.gserviceaccount.com",
        "private_key" => pem,
        "token_uri" => "https://oauth2.googleapis.com/token"
      },
      availability_calendar_id: "c",
      target_calendar_id: "c"
    ]

    merged = Keyword.merge(prev, Keyword.merge(base, opts))
    Application.put_env(:music_studio, MusicStudio.Scheduling, merged)
    on_exit(fn -> Application.put_env(:music_studio, MusicStudio.Scheduling, prev) end)
    :ok
  end

  @doc """
  Route the scheduling HTTP client at a stub. `calendar_fun` (a `Plug.Conn -> Plug.Conn`)
  handles calendar GET (list) and POST/PUT/DELETE (events); the service-account token
  endpoint is answered here automatically. Callable in `setup` or a test body (last wins).
  """
  def stub_google(calendar_fun) do
    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})
    on_exit(fn -> Application.delete_env(:music_studio, :scheduling_req_options) end)

    Req.Test.stub(GoogleAuth, fn conn ->
      if conn.host == "oauth2.googleapis.com" do
        Req.Test.json(conn, %{"access_token" => "at-test", "expires_in" => 3600})
      else
        calendar_fun.(conn)
      end
    end)
  end
end

defmodule MusicStudio.Scheduling.GoogleAuthTest do
  use MusicStudio.DataCase, async: false

  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    prev = Application.get_env(:music_studio, MusicStudio.Scheduling)

    Application.put_env(
      :music_studio,
      MusicStudio.Scheduling,
      Keyword.merge(prev,
        google_client_id: "cid",
        google_client_secret: "secret",
        google_redirect_uri: "http://localhost/cb"
      )
    )

    Application.put_env(:music_studio, :scheduling_req_options, plug: {Req.Test, GoogleAuth})

    on_exit(fn ->
      Application.put_env(:music_studio, MusicStudio.Scheduling, prev)
      Application.delete_env(:music_studio, :scheduling_req_options)
    end)

    :ok
  end

  test "authorize_url includes offline access and the configured client id" do
    url = GoogleAuth.authorize_url("state123")
    assert url =~ "access_type=offline"
    assert url =~ "state=state123"
    assert url =~ "scope="
    assert url =~ "client_id=cid"
  end

  test "exchange_code returns tokens parsed from Google" do
    Req.Test.stub(GoogleAuth, fn conn ->
      Req.Test.json(conn, %{
        "access_token" => "at-1",
        "refresh_token" => "rt-1",
        "expires_in" => 3600
      })
    end)

    assert {:ok, %{access_token: "at-1", refresh_token: "rt-1", expires_at: %DateTime{}}} =
             GoogleAuth.exchange_code("the-code")
  end

  test "fresh_access_token refreshes and persists when the cached token is expired" do
    {:ok, _} =
      Credentials.upsert(%{
        provider: "google",
        refresh_token: "rt-1",
        access_token: "old",
        access_token_expires_at: DateTime.add(DateTime.utc_now(), -10, :second)
      })

    Req.Test.stub(GoogleAuth, fn conn ->
      Req.Test.json(conn, %{"access_token" => "at-2", "expires_in" => 3600})
    end)

    assert {:ok, "at-2"} = Credentials.fresh_access_token()
    assert Credentials.get().access_token == "at-2"
  end
end

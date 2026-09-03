defmodule MusicStudio.Scheduling.GoogleAuthTest do
  use ExUnit.Case, async: false

  import MusicStudio.SchedulingStubs

  alias MusicStudio.Scheduling.{Credentials, GoogleAuth}

  setup do
    service_account_config(availability_calendar_id: "cal-x")
    :ok
  end

  test "mint_access_token signs a JWT, exchanges it, and returns a token" do
    stub_google(fn conn -> Req.Test.json(conn, %{"items" => []}) end)

    # Re-stub just the token endpoint to assert the grant shape.
    Req.Test.stub(GoogleAuth, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"
      assert body =~ "assertion="
      Req.Test.json(conn, %{"access_token" => "at-sa", "expires_in" => 3600})
    end)

    assert {:ok, %{access_token: "at-sa", expires_at: %DateTime{}}} =
             GoogleAuth.mint_access_token()
  end

  test "fresh_access_token mints via the service account" do
    stub_google(fn conn -> Req.Test.json(conn, %{"items" => []}) end)
    assert {:ok, "at-test"} = Credentials.fresh_access_token()
  end

  test "calendar ids come from config" do
    assert Credentials.availability_calendar_id() == "cal-x"
    assert Credentials.configured?()
  end
end

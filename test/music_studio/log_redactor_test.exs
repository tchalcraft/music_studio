defmodule MusicStudio.LogRedactorTest do
  use MusicStudioWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  require Logger

  test "redacts manage tokens from direct log calls" do
    log = capture_log(fn -> Logger.error("GET /book/manage/AbC-123_xyz") end)
    assert log =~ "/book/manage/[FILTERED]"
    refute log =~ "AbC-123_xyz"
  end

  test "redacts the token from Phoenix's request log line", %{conn: conn} do
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)

    log = capture_log([level: :info], fn -> get(conn, "/book/manage/secretTOKEN123") end)
    assert log =~ "/book/manage/[FILTERED]"
    refute log =~ "secretTOKEN123"
  end

  test "leaves other lines untouched" do
    assert MusicStudio.LogRedactor.redact("GET /book") == "GET /book"
  end
end

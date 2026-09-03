defmodule MusicStudio.Scheduling.ConfigTest do
  use ExUnit.Case, async: true

  test "scheduling defaults are configured" do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling)
    assert cfg[:studio_timezone] == "America/Vancouver"
    assert cfg[:slot_grid_minutes] == 30
    assert cfg[:buffer_minutes] == 15
    assert cfg[:min_notice_minutes] == 24 * 60
  end

  test "the Pacific time zone resolves (tzdata wired)" do
    assert {:ok, %DateTime{}} = DateTime.now("America/Vancouver")
  end

  test "scheduling config exposes the service-account keys" do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling)
    assert Keyword.has_key?(cfg, :service_account_key)
    assert Keyword.has_key?(cfg, :availability_calendar_id)
    assert Keyword.has_key?(cfg, :target_calendar_id)
    assert cfg[:google_token_url] == "https://oauth2.googleapis.com/token"
  end
end

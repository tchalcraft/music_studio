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
end

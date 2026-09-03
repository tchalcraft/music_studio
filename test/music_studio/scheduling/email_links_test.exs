defmodule MusicStudio.Scheduling.EmailLinksTest do
  use ExUnit.Case, async: true

  test "scheduling config exposes website_url and a social keyword list" do
    cfg = Application.get_env(:music_studio, MusicStudio.Scheduling)
    assert Keyword.has_key?(cfg, :website_url)
    assert is_list(cfg[:social])
    assert Keyword.has_key?(cfg[:social], :instagram)
    assert Keyword.has_key?(cfg[:social], :facebook)
    assert Keyword.has_key?(cfg[:social], :youtube)
  end
end

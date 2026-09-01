defmodule MusicStudio.Scheduling.AvailabilityTest do
  use ExUnit.Case, async: true

  alias MusicStudio.Scheduling.{Availability, Slot}

  defp dt(h, m), do: DateTime.new!(~D[2026-09-10], Time.new!(h, m, 0), "Etc/UTC")

  defp base(overrides) do
    Map.merge(
      %{
        blocks: [],
        booked: [],
        duration_minutes: 60,
        grid_minutes: 30,
        buffer_minutes: 15,
        min_notice_minutes: 0,
        now: dt(0, 0)
      },
      overrides
    )
  end

  test "tiles a block on the 30-min grid, keeping only starts whose duration fits" do
    slots = Availability.compute(base(%{blocks: [%{starts_at: dt(15, 0), ends_at: dt(17, 0)}]}))
    assert Enum.map(slots, & &1.starts_at) == [dt(15, 0), dt(15, 30), dt(16, 0)]
    assert %Slot{starts_at: %DateTime{}, ends_at: %DateTime{}} = hd(slots)
    assert hd(slots).ends_at == dt(16, 0)
  end

  test "a booked lesson removes overlapping starts, expanded by the buffer" do
    slots =
      Availability.compute(
        base(%{
          duration_minutes: 30,
          blocks: [%{starts_at: dt(15, 0), ends_at: dt(17, 0)}],
          booked: [%{starts_at: dt(16, 0), ends_at: dt(16, 30)}]
        })
      )

    starts = Enum.map(slots, & &1.starts_at)
    refute dt(15, 30) in starts
    refute dt(16, 30) in starts
    assert dt(15, 0) in starts
  end

  test "drops starts inside the minimum-notice window" do
    slots =
      Availability.compute(
        base(%{
          now: dt(14, 0),
          min_notice_minutes: 120,
          blocks: [%{starts_at: dt(15, 0), ends_at: dt(17, 0)}]
        })
      )

    assert Enum.map(slots, & &1.starts_at) == [dt(16, 0)]
  end
end

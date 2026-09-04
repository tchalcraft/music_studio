defmodule MusicStudio.Scheduling.AvailabilityPropertyTest do
  @moduledoc """
  Property-based invariants for the pure slot computation. `Availability.compute/1` owns
  four guarantees, and these hold for *any* combination of blocks, bookings, and rules:

    1. grid alignment — every slot starts on the grid
    2. containment  — every slot lies fully inside one of the given blocks
    3. min-notice   — no slot starts before now + min_notice
    4. no-overlap   — no slot overlaps a booked interval expanded by the buffer

  (The Mon–Fri 2–9pm working-hours rule is NOT enforced here — it lives in whatever builds
  the `blocks`; `compute/1` only promises slots stay within the blocks it is handed.)
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias MusicStudio.Scheduling.Availability

  @epoch ~U[2026-09-10 00:00:00Z]

  # A DateTime built from a whole number of minutes past a fixed epoch — keeps generation
  # cheap and second-free, matching how the app grids on :00/:30 boundaries.
  defp minutes(n), do: DateTime.add(@epoch, n, :minute)

  defp interval_gen do
    gen all(start_min <- integer(0..20_160), len <- integer(15..240)) do
      %{starts_at: minutes(start_min), ends_at: minutes(start_min + len)}
    end
  end

  defp args_gen do
    gen all(
          blocks <- list_of(interval_gen(), max_length: 4),
          booked <- list_of(interval_gen(), max_length: 6),
          duration <- member_of([30, 45, 60]),
          grid <- member_of([15, 30]),
          buffer <- member_of([0, 15]),
          min_notice <- member_of([0, 60, 1440]),
          now_min <- integer(0..20_160)
        ) do
      %{
        blocks: blocks,
        booked: booked,
        duration_minutes: duration,
        grid_minutes: grid,
        buffer_minutes: buffer,
        min_notice_minutes: min_notice,
        now: minutes(now_min)
      }
    end
  end

  defp grid_aligned?(dt, grid_minutes) do
    rem(DateTime.diff(dt, @epoch, :second), grid_minutes * 60) == 0
  end

  defp within_any_block?(slot, blocks) do
    Enum.any?(blocks, fn b ->
      DateTime.compare(slot.starts_at, b.starts_at) != :lt and
        DateTime.compare(slot.ends_at, b.ends_at) != :gt
    end)
  end

  defp overlaps?(a, b) do
    DateTime.compare(a.starts_at, b.ends_at) == :lt and
      DateTime.compare(b.starts_at, a.ends_at) == :lt
  end

  property "every computed slot satisfies grid / containment / min-notice / no-overlap" do
    check all(args <- args_gen()) do
      slots = Availability.compute(args)
      cutoff = DateTime.add(args.now, args.min_notice_minutes, :minute)

      buffered =
        Enum.map(args.booked, fn b ->
          %{
            starts_at: DateTime.add(b.starts_at, -args.buffer_minutes * 60, :second),
            ends_at: DateTime.add(b.ends_at, args.buffer_minutes * 60, :second)
          }
        end)

      for slot <- slots do
        assert grid_aligned?(slot.starts_at, args.grid_minutes)
        assert DateTime.diff(slot.ends_at, slot.starts_at, :minute) == args.duration_minutes
        assert within_any_block?(slot, args.blocks)
        assert DateTime.compare(slot.starts_at, cutoff) != :lt
        refute Enum.any?(buffered, &overlaps?(slot, &1))
      end

      # starts are unique and sorted
      starts = Enum.map(slots, &DateTime.to_unix(&1.starts_at))
      assert starts == Enum.sort(starts)
      assert starts == Enum.uniq(starts)
    end
  end
end

defmodule MusicStudio.Scheduling.Availability do
  @moduledoc """
  Pure slot computation. Given available blocks (from the Google Availability calendar),
  already-booked lessons, and rules (grid, buffer, minimum notice), returns the bookable
  `Slot`s. No I/O — every input is passed in, so it is exhaustively unit-testable.

  All datetimes are UTC. Grid alignment is done in UTC; for America/Vancouver (whole-hour
  offsets) this coincides with local :00/:30 boundaries.
  """
  alias MusicStudio.Scheduling.Slot

  @type interval :: %{starts_at: DateTime.t(), ends_at: DateTime.t()}

  @spec compute(map()) :: [Slot.t()]
  def compute(%{blocks: blocks} = args) do
    duration = args.duration_minutes
    grid_s = args.grid_minutes * 60
    buffer_s = args.buffer_minutes * 60
    cutoff = DateTime.add(args.now, args.min_notice_minutes, :minute)
    busy = Enum.map(args.booked, &expand(&1, buffer_s))

    blocks
    |> Enum.flat_map(&candidate_starts(&1, grid_s, duration))
    |> Enum.filter(fn slot ->
      DateTime.compare(slot.starts_at, cutoff) != :lt and
        not Enum.any?(busy, &overlaps?(slot, &1))
    end)
    |> Enum.uniq_by(& &1.starts_at)
    |> Enum.sort_by(&DateTime.to_unix(&1.starts_at))
  end

  defp candidate_starts(%{starts_at: block_start, ends_at: block_end}, grid_s, duration) do
    first = round_up(block_start, grid_s)

    first
    |> Stream.iterate(&DateTime.add(&1, grid_s, :second))
    |> Stream.map(fn start ->
      %Slot{starts_at: start, ends_at: DateTime.add(start, duration, :minute)}
    end)
    |> Stream.take_while(fn slot -> DateTime.compare(slot.ends_at, block_end) != :gt end)
    |> Enum.to_list()
  end

  defp round_up(dt, grid_s) do
    epoch = DateTime.to_unix(dt)

    case rem(epoch, grid_s) do
      0 -> dt
      r -> DateTime.from_unix!(epoch + (grid_s - r))
    end
  end

  defp expand(%{starts_at: s, ends_at: e}, buffer_s) do
    %{starts_at: DateTime.add(s, -buffer_s, :second), ends_at: DateTime.add(e, buffer_s, :second)}
  end

  # Half-open intervals overlap when a.start < b.end and b.start < a.end.
  defp overlaps?(a, b) do
    DateTime.compare(a.starts_at, b.ends_at) == :lt and
      DateTime.compare(b.starts_at, a.ends_at) == :lt
  end
end

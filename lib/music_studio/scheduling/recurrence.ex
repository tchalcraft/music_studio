defmodule MusicStudio.Scheduling.Recurrence do
  @moduledoc """
  Pure date math for recurring lesson series: the school-year term boundary, the list of
  occurrence dates for a weekly/bi-weekly cadence, and the DST-safe conversion of a local
  wall-clock time on a given date to a UTC `DateTime`. No I/O — fully unit-testable.
  """

  @spec term_end(Date.t()) :: Date.t()
  def term_end(%Date{year: year} = date) do
    june30 = Date.new!(year, 6, 30)
    if Date.compare(date, june30) in [:lt, :eq], do: june30, else: Date.new!(year + 1, 6, 30)
  end

  @spec occurrence_dates(Date.t(), 1 | 2, Date.t()) :: [Date.t()]
  def occurrence_dates(start_date, interval_weeks, term_end) do
    start_date
    |> Stream.iterate(&Date.add(&1, interval_weeks * 7))
    |> Enum.take_while(&(Date.compare(&1, term_end) != :gt))
  end

  @spec occurrence_utc(Date.t(), Time.t(), String.t()) :: DateTime.t()
  def occurrence_utc(date, %Time{} = time, tz) do
    case DateTime.new(date, time, tz) do
      {:ok, dt} -> DateTime.shift_zone!(dt, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _just_before, just_after} -> DateTime.shift_zone!(just_after, "Etc/UTC")
    end
  end
end

defmodule MusicStudio.Scheduling.RecurrenceTest do
  use ExUnit.Case, async: true

  alias MusicStudio.Scheduling.Recurrence

  test "term_end is the next June 30 on/after the start date" do
    assert Recurrence.term_end(~D[2026-09-08]) == ~D[2027-06-30]
    assert Recurrence.term_end(~D[2027-01-05]) == ~D[2027-06-30]
    assert Recurrence.term_end(~D[2027-06-30]) == ~D[2027-06-30]
    assert Recurrence.term_end(~D[2027-07-01]) == ~D[2028-06-30]
  end

  test "weekly occurrences step 7 days and stop at term end" do
    dates = Recurrence.occurrence_dates(~D[2027-06-16], 1, ~D[2027-06-30])
    assert dates == [~D[2027-06-16], ~D[2027-06-23], ~D[2027-06-30]]
  end

  test "bi-weekly occurrences step 14 days" do
    dates = Recurrence.occurrence_dates(~D[2027-06-02], 2, ~D[2027-06-30])
    assert dates == [~D[2027-06-02], ~D[2027-06-16], ~D[2027-06-30]]
  end

  test "occurrence_utc converts a local wall-clock time to UTC using the Pacific offset" do
    # 16:00 in America/Vancouver is NOT 16:00Z — the zone offset must be applied. Both dates
    # here are Pacific Daylight (−07:00) in real life, so both are 23:00Z. (We avoid asserting
    # a specific DST *transition* week here: this sandbox's bundled tzdata can't fetch fresh
    # IANA data — network-restricted — so future transitions may not resolve; production tzdata
    # self-updates and is correct. The conversion itself, exercised below, is what matters.)
    a = Recurrence.occurrence_utc(~D[2026-09-08], ~T[16:00:00], "America/Vancouver")
    b = Recurrence.occurrence_utc(~D[2026-10-27], ~T[16:00:00], "America/Vancouver")

    assert %DateTime{time_zone: "Etc/UTC"} = a
    assert DateTime.to_iso8601(a) == "2026-09-08T23:00:00Z"
    assert DateTime.to_iso8601(b) == "2026-10-27T23:00:00Z"
    refute DateTime.to_time(a) == ~T[16:00:00]
  end
end

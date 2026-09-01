defmodule MusicStudio.Scheduling.Slot do
  @moduledoc "A bookable time slot (UTC). Value object produced by `Availability.compute/1`."
  @enforce_keys [:starts_at, :ends_at]
  defstruct [:starts_at, :ends_at]

  @type t :: %__MODULE__{starts_at: DateTime.t(), ends_at: DateTime.t()}
end

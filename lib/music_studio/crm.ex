defmodule MusicStudio.CRM do
  @moduledoc """
  Marketing/CRM funnel: campaigns and touchpoints, plus lead→student conversion.
  Complements `MusicStudio.Leads` (which owns the public inquiry form and the `Lead`
  schema). List functions exclude soft-deleted rows where applicable.
  """
  import Ecto.Query, warn: false

  alias MusicStudio.CRM.Campaign
  alias MusicStudio.CRM.Touchpoint
  alias MusicStudio.Leads.Lead
  alias MusicStudio.Repo
  alias MusicStudio.Teaching
  alias MusicStudio.Teaching.Student

  ## Campaigns

  def list_campaigns, do: Repo.all(from c in Campaign, where: is_nil(c.deleted_at))
  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def change_campaign(%Campaign{} = c \\ %Campaign{}, attrs \\ %{}),
    do: Campaign.changeset(c, attrs)

  def create_campaign(attrs \\ %{}),
    do: %Campaign{} |> Campaign.changeset(attrs) |> Repo.insert()

  def update_campaign(%Campaign{} = c, attrs),
    do: c |> Campaign.changeset(attrs) |> Repo.update()

  ## Touchpoints

  def list_touchpoints,
    do: Repo.all(from t in Touchpoint, order_by: [desc: t.occurred_at])

  def get_touchpoint!(id), do: Repo.get!(Touchpoint, id)

  def change_touchpoint(%Touchpoint{} = t \\ %Touchpoint{}, attrs \\ %{}),
    do: Touchpoint.changeset(t, attrs)

  def create_touchpoint(attrs \\ %{}),
    do: %Touchpoint{} |> Touchpoint.changeset(attrs) |> Repo.insert()

  ## Conversion

  @doc """
  Converts a `Lead` into a `Student`: creates the student (carrying `lead_id`), then marks
  the lead `:converted` and links `converted_student_id`. Runs in a transaction so the two
  sides stay consistent. `student_attrs` supplements fields derived from the lead.
  """
  def convert_lead_to_student(%Lead{} = lead, student_attrs \\ %{}) do
    {first, last} = split_name(lead.name)

    derived = %{
      "first_name" => student_attrs["first_name"] || first,
      "last_name" => student_attrs["last_name"] || last,
      "email" => student_attrs["email"] || lead.email,
      "status" => "active",
      "lead_id" => lead.id
    }

    attrs = Map.merge(derived, student_attrs)

    Repo.transaction(fn ->
      with {:ok, %Student{} = student} <- Teaching.create_student(attrs),
           {:ok, updated_lead} <-
             lead
             |> Lead.funnel_changeset(%{status: :converted, converted_student_id: student.id})
             |> Repo.update() do
        {student, updated_lead}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Naively split a lead's single name field into first/last for the derived student.
  defp split_name(nil), do: {nil, nil}

  defp split_name(name) do
    case name |> String.trim() |> String.split(" ", parts: 2) do
      [first, last] -> {first, last}
      [first] -> {first, nil}
      _ -> {nil, nil}
    end
  end
end

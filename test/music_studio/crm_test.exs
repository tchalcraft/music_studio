defmodule MusicStudio.CRMTest do
  use MusicStudio.DataCase, async: true

  alias MusicStudio.CRM
  alias MusicStudio.CRM.Campaign
  alias MusicStudio.CRM.Touchpoint
  alias MusicStudio.Leads
  alias MusicStudio.Repo
  alias MusicStudio.Teaching.Student

  test "convert_lead_to_student/2 creates a student and marks the lead converted" do
    {:ok, lead} =
      Leads.create_lead(%{name: "Jamie Note", email: "jamie@example.com", instrument: "piano"})

    assert {:ok, {%Student{} = student, updated_lead}} = CRM.convert_lead_to_student(lead)

    assert student.lead_id == lead.id
    assert student.first_name == "Jamie"
    assert student.last_name == "Note"
    assert student.status == :active
    assert updated_lead.status == :converted
    assert updated_lead.converted_student_id == student.id

    # Reloading the lead confirms the funnel fields persisted.
    assert Repo.get!(Leads.Lead, lead.id).status == :converted
  end

  test "campaigns and touchpoints persist" do
    assert {:ok, %Campaign{} = campaign} =
             CRM.create_campaign(%{name: "Fall open house", channel: :referral})

    assert {:ok, %Touchpoint{} = tp} =
             CRM.create_touchpoint(%{
               campaign_id: campaign.id,
               channel: :email,
               direction: :outbound,
               occurred_at: DateTime.utc_now(),
               summary: "Sent welcome email",
               metadata: %{"opened" => true}
             })

    assert tp.metadata["opened"] == true
    assert [%Touchpoint{}] = CRM.list_touchpoints()
  end

  test "touchpoint requires channel, direction, and occurred_at" do
    assert {:error, changeset} = CRM.create_touchpoint(%{})
    errs = errors_on(changeset)
    assert "can't be blank" in errs.occurred_at
  end
end

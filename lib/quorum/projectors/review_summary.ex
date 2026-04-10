defmodule Quorum.Projectors.ReviewSummary do
  use Commanded.Projections.Ecto,
    application: Quorum.CommandedApp,
    repo: Quorum.Repo,
    name: "Quorum.Projectors.ReviewSummary"

  alias Quorum.Events.{ReviewRequested, SpecialistCompleted, SynthesisCompleted, ReviewCompleted}
  alias Quorum.Projections.ReviewSummary

  project(%ReviewRequested{} = evt, _metadata, fn multi ->
    Ecto.Multi.insert(multi, :review_summary, %ReviewSummary{
      review_id: evt.review_id,
      code: evt.code,
      language: evt.language,
      status: "pending",
      requested_at: evt.requested_at
    })
  end)

  project(%SpecialistCompleted{} = evt, _metadata, fn multi ->
    field =
      case evt.specialist do
        "Security" -> :security_review
        "Logic" -> :logic_review
        "Style" -> :style_review
      end

    review_data = %{
      review: evt.review,
      error: evt.error,
      completed_at: evt.completed_at
    }

    Ecto.Multi.update_all(multi, :specialist, review_summary_query(evt.review_id),
      set: [{field, review_data}]
    )
  end)

  project(%SynthesisCompleted{} = evt, _metadata, fn multi ->
    synthesis_data = %{
      synthesis: evt.synthesis,
      error: evt.error,
      completed_at: evt.completed_at
    }

    Ecto.Multi.update_all(multi, :synthesis, review_summary_query(evt.review_id),
      set: [synthesis: synthesis_data]
    )
  end)

  project(%ReviewCompleted{} = evt, _metadata, fn multi ->
    Ecto.Multi.update_all(multi, :complete, review_summary_query(evt.review_id),
      set: [status: "complete", completed_at: evt.completed_at]
    )
  end)

  defp review_summary_query(review_id) do
    import Ecto.Query
    from(r in ReviewSummary, where: r.review_id == ^review_id)
  end
end

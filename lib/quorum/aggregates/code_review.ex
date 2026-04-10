defmodule Quorum.Aggregates.CodeReview do
  defstruct [
    :review_id,
    :code,
    :language,
    :status,
    specialists_completed: MapSet.new()
  ]

  alias Quorum.Aggregates.CodeReview
  alias Quorum.Commands.{RequestReview, RecordSpecialistReview, RecordSynthesis}
  alias Quorum.Events.{ReviewRequested, SpecialistCompleted, SynthesisCompleted, ReviewCompleted}

  # ── Commands ──

  def execute(%CodeReview{review_id: nil}, %RequestReview{} = cmd) do
    %ReviewRequested{
      review_id: cmd.review_id,
      code: cmd.code,
      language: cmd.language,
      requested_at: DateTime.utc_now()
    }
  end

  def execute(%CodeReview{status: :pending}, %RecordSpecialistReview{} = cmd) do
    %SpecialistCompleted{
      review_id: cmd.review_id,
      specialist: cmd.specialist,
      review: cmd.review,
      error: cmd.error,
      completed_at: DateTime.utc_now()
    }
  end

  def execute(%CodeReview{status: :pending}, %RecordSynthesis{} = cmd) do
    [
      %SynthesisCompleted{
        review_id: cmd.review_id,
        synthesis: cmd.synthesis,
        error: cmd.error,
        completed_at: DateTime.utc_now()
      },
      %ReviewCompleted{
        review_id: cmd.review_id,
        completed_at: DateTime.utc_now()
      }
    ]
  end

  # ── Events ──

  def apply(%CodeReview{} = state, %ReviewRequested{} = evt) do
    %{state |
      review_id: evt.review_id,
      code: evt.code,
      language: evt.language,
      status: :pending
    }
  end

  def apply(%CodeReview{} = state, %SpecialistCompleted{} = evt) do
    %{state | specialists_completed: MapSet.put(state.specialists_completed, evt.specialist)}
  end

  def apply(%CodeReview{} = state, %SynthesisCompleted{}) do
    state
  end

  def apply(%CodeReview{} = state, %ReviewCompleted{}) do
    %{state | status: :complete}
  end
end

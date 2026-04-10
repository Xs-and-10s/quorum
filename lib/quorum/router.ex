defmodule Quorum.Router do
  use Commanded.Commands.Router

  alias Quorum.Aggregates.CodeReview
  alias Quorum.Commands.{RequestReview, RecordSpecialistReview, RecordSynthesis}

  dispatch RequestReview, to: CodeReview, identity: :review_id
  dispatch RecordSpecialistReview, to: CodeReview, identity: :review_id
  dispatch RecordSynthesis, to: CodeReview, identity: :review_id
end

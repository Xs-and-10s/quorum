defmodule Quorum.Commands.RequestReview do
  defstruct [:review_id, :code, :language]
end

defmodule Quorum.Commands.RecordSpecialistReview do
  defstruct [:review_id, :specialist, :review, :error]
end

defmodule Quorum.Commands.RecordSynthesis do
  defstruct [:review_id, :synthesis, :error]
end

defmodule Quorum.Events.ReviewRequested do
  @derive Jason.Encoder
  defstruct [:review_id, :code, :language, :requested_at]
end

defmodule Quorum.Events.SpecialistCompleted do
  @derive Jason.Encoder
  defstruct [:review_id, :specialist, :review, :error, :completed_at]
end

defmodule Quorum.Events.SynthesisCompleted do
  @derive Jason.Encoder
  defstruct [:review_id, :synthesis, :error, :completed_at]
end

defmodule Quorum.Events.ReviewCompleted do
  @derive Jason.Encoder
  defstruct [:review_id, :completed_at]
end

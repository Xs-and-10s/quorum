defmodule Quorum.Projections.ReviewSummary do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:review_id, :string, autogenerate: false}

  schema "review_summaries" do
    field :code, :string
    field :language, :string
    field :status, :string, default: "pending"
    field :security_review, :map
    field :logic_review, :map
    field :style_review, :map
    field :synthesis, :map
    field :requested_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, [
      :review_id, :code, :language, :status,
      :security_review, :logic_review, :style_review,
      :synthesis, :requested_at, :completed_at
    ])
    |> validate_required([:review_id, :code, :language])
  end
end

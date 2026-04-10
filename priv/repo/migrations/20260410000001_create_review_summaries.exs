defmodule Quorum.Repo.Migrations.CreateReviewSummaries do
  use Ecto.Migration

  def change do
    create table(:review_summaries, primary_key: false) do
      add :review_id, :string, primary_key: true
      add :code, :text, null: false
      add :language, :string, null: false, default: "elixir"
      add :status, :string, null: false, default: "pending"
      add :security_review, :map
      add :logic_review, :map
      add :style_review, :map
      add :synthesis, :map
      add :requested_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:review_summaries, [:status])
    create index(:review_summaries, [:requested_at])
  end
end

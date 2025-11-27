defmodule WizHome.Lights.Bulb do
  @moduledoc """
  Schema for Wiz smart light bulbs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "bulbs" do
    field :ip, :string
    field :name, :string
    field :last_color_r, :integer
    field :last_color_g, :integer
    field :last_color_b, :integer
    field :last_brightness, :integer
    field :last_temperature, :integer

    timestamps()
  end

  @doc false
  def changeset(bulb, attrs) do
    bulb
    |> cast(attrs, [:ip, :name, :last_color_r, :last_color_g, :last_color_b, :last_brightness, :last_temperature])
    |> validate_required([:ip])
    |> validate_format(:ip, ~r/^(\d{1,3}\.){3}\d{1,3}$/, message: "must be a valid IP address")
    |> validate_inclusion(:last_color_r, 0..255, message: "must be between 0 and 255")
    |> validate_inclusion(:last_color_g, 0..255, message: "must be between 0 and 255")
    |> validate_inclusion(:last_color_b, 0..255, message: "must be between 0 and 255")
    |> validate_inclusion(:last_brightness, 10..100, message: "must be between 10 and 100")
    |> validate_inclusion(:last_temperature, 2200..6500, message: "must be between 2200 and 6500")
    |> unique_constraint(:ip)
  end

  @doc """
  Changeset for updating only the color fields.
  """
  def color_changeset(bulb, attrs) do
    bulb
    |> cast(attrs, [:last_color_r, :last_color_g, :last_color_b, :last_brightness, :last_temperature])
    |> validate_inclusion(:last_color_r, 0..255, message: "must be between 0 and 255")
    |> validate_inclusion(:last_color_g, 0..255, message: "must be between 0 and 255")
    |> validate_inclusion(:last_color_b, 0..255, message: "must be between 0 and 255")
    |> validate_inclusion(:last_brightness, 10..100, message: "must be between 10 and 100")
    |> validate_inclusion(:last_temperature, 2200..6500, message: "must be between 2200 and 6500")
  end
end

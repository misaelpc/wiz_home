defmodule WizHome.Lights do
  @moduledoc """
  Context module for managing Wiz smart light bulbs.
  """
  import Ecto.Query, warn: false
  alias WizHome.Repo
  alias WizHome.Lights.Bulb

  @doc """
  Returns the list of bulbs.
  """
  def list_bulbs do
    Repo.all(Bulb)
  end

  @doc """
  Gets a single bulb.
  """
  def get_bulb!(id), do: Repo.get!(Bulb, id)

  @doc """
  Gets a bulb by IP address.
  """
  def get_bulb_by_ip(ip) do
    Repo.get_by(Bulb, ip: ip)
  end

  @doc """
  Creates a bulb.
  """
  def create_bulb(attrs \\ %{}) do
    %Bulb{}
    |> Bulb.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a bulb.
  """
  def update_bulb(%Bulb{} = bulb, attrs) do
    bulb
    |> Bulb.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates only the color fields of a bulb.
  """
  def update_bulb_color(%Bulb{} = bulb, attrs) do
    bulb
    |> Bulb.color_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bulb.
  """
  def delete_bulb(%Bulb{} = bulb) do
    Repo.delete(bulb)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking bulb changes.
  """
  def change_bulb(%Bulb{} = bulb, attrs \\ %{}) do
    Bulb.changeset(bulb, attrs)
  end
end





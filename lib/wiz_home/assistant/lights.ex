defmodule WizHome.Assistant.Lights do
  @moduledoc """
  Seam the voice assistant's `Brain.Actions` calls into to actually drive the
  bulbs — turns every registered bulb on/off via the same UDP path
  (`WizHome.set_state/2`) the LiveView dashboard's toggle switch uses.
  """

  alias WizHome.Lights

  @topic "lights:updates"

  def topic, do: @topic

  @spec on() :: :ok
  def on, do: set_all(true)

  @spec off() :: :ok
  def off, do: set_all(false)

  defp set_all(state) do
    Lights.list_bulbs()
    |> Enum.each(&WizHome.set_state(&1.ip, state))

    Phoenix.PubSub.broadcast(WizHome.PubSub, @topic, :lights_changed)
    :ok
  end
end

defmodule WizHome.Assistant.Supervisor do
  @moduledoc """
  Supervises the local voice assistant's listener and orchestrator together.

  `:rest_for_one` so a `WakeWord.Listener` crash also restarts the
  `Conversation.Orchestrator` — otherwise a running wake pipeline would keep
  sending scores to the listener's stale (dead) pid after a restart.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      WizHome.Assistant.WakeWord.Listener,
      WizHome.Assistant.Conversation.Orchestrator
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

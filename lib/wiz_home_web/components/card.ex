defmodule WizHomeWeb.Components.Card do
  @moduledoc """
  Renders a card component with Taildash styling.
  """
  use WizHomeWeb, :html

  attr :class, :string, default: nil
  attr :title, :string, default: nil
  slot :inner_block, required: true
  slot :actions

  def card(assigns) do
    ~H"""
    <div class={[
      "rounded-lg border border-stroke dark:border-strokedark bg-white dark:bg-boxdark",
      @class
    ]}>
      <div :if={@title || @actions != []} class="flex items-center justify-between border-b border-stroke dark:border-strokedark px-6 py-4.5">
        <h3 :if={@title} class="font-semibold text-title-sm text-black dark:text-white">
          {@title}
        </h3>
        <div :if={@actions != []} class="flex items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      <div class="p-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end

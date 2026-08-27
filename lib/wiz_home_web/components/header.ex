defmodule WizHomeWeb.Components.Header do
  @moduledoc """
  Renders the glass top navigation shared by home and register.
  """
  use WizHomeWeb, :html

  attr :current_section, :string, default: "home"
  attr :assistant_status, :atom, default: :idle

  def header(assigns) do
    ~H"""
    <section
      id="home-top-nav"
      class="rounded-[20px] border border-white/45 bg-[linear-gradient(192deg,rgba(69,76,100,0.75)_4%,rgba(69,76,100,0.05)_76%),linear-gradient(90deg,rgba(255,255,255,0.22)_0%,rgba(255,255,255,0.22)_100%)] px-5 py-4 shadow-[15px_13px_21.2px_-4px_rgba(0,0,0,0.25)] backdrop-blur-[25px] sm:px-8"
    >
      <div class="flex flex-wrap items-center justify-between gap-6">
        <.link id="brand-home" patch={~p"/"} class="flex items-center gap-3">
          <div class="flex h-[60px] w-[72px] items-center justify-center rounded-2xl bg-white/90">
            <.icon name="hero-home-modern" class="h-10 w-10 text-[#3b60e4]" />
          </div>
          <p class="font-['Space_Grotesk'] text-2xl font-bold leading-[1.1] text-white sm:text-[30px]">
            Home<br />Controller
          </p>
        </.link>

        <.assistant_indicator status={@assistant_status} />

        <nav class="hidden items-center gap-10 text-[20px] text-white/80 lg:flex">
          <.link
            id="nav-my-home"
            patch={~p"/"}
            class={[
              "transition-opacity hover:opacity-80",
              @current_section == "home" && "font-bold text-white"
            ]}
          >
            My home
          </.link>
          <a
            id="nav-notifications"
            href="#"
            class="transition-opacity hover:opacity-80"
          >
            Notifications
          </a>
          <a id="nav-settings" href="#" class="transition-opacity hover:opacity-80">
            Settings
          </a>
        </nav>

        <div class="flex items-center gap-5">
          <.link
            id="nav-add-light"
            patch={~p"/register"}
            class={[
              "inline-flex h-[50px] items-center rounded-[30px] border border-white/80 bg-gradient-to-r from-[#3b60e4] to-[#7765e3] px-6 text-lg font-medium text-white transition-transform duration-300 hover:-translate-y-0.5",
              @current_section == "register" && "ring-2 ring-white/80"
            ]}
          >
            <span class="mr-2 text-xl">+</span>
            <span>Add light</span>
          </.link>

          <div class="hidden items-center gap-4 sm:flex">
            <p class="text-xl font-semibold text-white">Username</p>
            <img
              src={~p"/images/profile.svg"}
              alt="Profile"
              class="h-[61px] w-[61px] rounded-full border border-white/60 object-cover"
            />
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :status, :atom, default: :idle

  defp assistant_indicator(assigns) do
    ~H"""
    <div
      id="assistant-status"
      class="flex items-center gap-2 rounded-full border border-white/45 bg-white/10 px-4 py-2"
      title="Beemo voice assistant status"
    >
      <span class={[
        "h-[10px] w-[10px] rounded-full",
        assistant_dot_class(@status)
      ]}>
      </span>
      <span class="text-sm font-medium text-white/90">
        {assistant_label(@status)}
      </span>
    </div>
    """
  end

  defp assistant_dot_class(:listening), do: "bg-emerald-400"
  defp assistant_dot_class(:capturing), do: "bg-amber-400 animate-pulse"
  defp assistant_dot_class(:transcribing), do: "bg-sky-400 animate-pulse"
  defp assistant_dot_class(_), do: "bg-white/40"

  defp assistant_label(:listening), do: "Listening for \"Hey Beemo\""
  defp assistant_label(:capturing), do: "Listening..."
  defp assistant_label(:transcribing), do: "Thinking..."
  defp assistant_label(_), do: "Voice assistant offline"
end

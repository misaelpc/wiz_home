defmodule WizHomeWeb.LightsLive do
  use Phoenix.LiveView,
    layout: {WizHomeWeb.Layouts, :dashboard}

  use WizHomeWeb, :html

  alias WizHome.Lights
  alias WizHome.Lights.Bulb

  import WizHomeWeb.Components.Card

  @default_color %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}
  @mood_image_map %{
    deep_blue: "http://localhost:3845/assets/0b0bc3ce7861c106e0cc441745db66c1e2f87a15.png",
    soft_teal: "http://localhost:3845/assets/ff4f8c29046cf6a06ad1bc40427f0bf1356008cc.png",
    cool_green: "http://localhost:3845/assets/a5ebc4619eb2941d17bbc4a8a518d9817b532c03.png",
    muted_cyan: "http://localhost:3845/assets/2af0e6d9e4f82d75f7f19b94d0c9254661c182e6.png",
    warm_white: "http://localhost:3845/assets/38b5e4da69a5e63791f6ebd6f1f52e8e78b67f65.png",
    pure_white: "http://localhost:3845/assets/826d11ede70b3c6f6bdd2c94e9b45f911eeb5ff7.png"
  }

  @impl true
  def mount(_params, _session, socket) do
    bulbs = Lights.list_bulbs()
    bulb_states = load_bulb_states(bulbs)
    default_hsl = rgb_to_hsl(@default_color)

    socket =
      socket
      |> assign(:bulbs, bulbs)
      |> assign(:bulb_states, bulb_states)
      |> assign(:all_lights_on, all_lights_on?(bulbs, bulb_states))
      |> assign(:selected_bulb, nil)
      |> assign(:color, @default_color)
      |> assign(:color_hsl, default_hsl)
      |> assign(:original_color, @default_color)
      |> assign(:form, to_form(Bulb.changeset(%Bulb{}, %{})))
      |> assign(:current_section, "register")
      |> assign(:sidebar_open, false)
      |> assign(:user_dropdown_open, false)
      |> assign(:show_color_modal, false)
      |> assign(:color_modal_mode, :single)
      |> assign(:picker_anchor_id, nil)
      |> assign(:mood_presets, mood_presets())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    section = Map.get(params, "section", "register")

    # Validate section - default to register if invalid
    current_section = if section in ["register", "admin"], do: section, else: "register"

    socket = assign(socket, :current_section, current_section)

    socket =
      if current_section == "admin" do
        refresh_lights(socket)
      else
        socket
      end

    socket =
      if current_section != section do
        push_patch(socket, to: ~p"/lights/#{current_section}")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :user_dropdown_open, !socket.assigns.user_dropdown_open)}
  end

  @impl true
  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :user_dropdown_open, false)}
  end

  @impl true
  def handle_event("add_bulb", %{"bulb" => bulb_params}, socket) do
    case Lights.create_bulb(bulb_params) do
      {:ok, _bulb} ->
        socket =
          socket
          |> put_flash(:info, "Bulb added successfully")
          |> refresh_lights()
          |> assign(:form, to_form(Bulb.changeset(%Bulb{}, %{})))

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> put_flash(:error, "Failed to add bulb")
          |> assign(:form, to_form(changeset))

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_bulb", %{"id" => id}, socket) do
    bulb = Lights.get_bulb!(id)
    Lights.delete_bulb(bulb)

    selected_bulb =
      if socket.assigns.selected_bulb && socket.assigns.selected_bulb.id == String.to_integer(id) do
        nil
      else
        socket.assigns.selected_bulb
      end

    socket =
      socket
      |> put_flash(:info, "Bulb removed")
      |> refresh_lights()
      |> assign(:selected_bulb, selected_bulb)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_bulb", %{"id" => id} = params, socket) do
    bulb = Lights.get_bulb!(id)
    picker_anchor_id = Map.get(params, "anchor", "color-bulb-#{id}")

    color =
      cond do
        # If temperature is set, use it
        bulb.last_temperature ->
          {r, g, b} = kelvin_to_rgb(bulb.last_temperature)

          %{
            r: r,
            g: g,
            b: b,
            brightness: bulb.last_brightness || 75,
            temperature: bulb.last_temperature
          }

        # Otherwise use RGB if available
        bulb.last_color_r && bulb.last_color_g && bulb.last_color_b && bulb.last_brightness ->
          %{
            r: bulb.last_color_r,
            g: bulb.last_color_g,
            b: bulb.last_color_b,
            brightness: bulb.last_brightness,
            temperature: nil
          }

        # Default
        true ->
          %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}
      end

    hsl = rgb_to_hsl(color)

    socket =
      socket
      |> assign(:selected_bulb, bulb)
      |> assign(:color, color)
      # Store original color for cancel
      |> assign(:original_color, color)
      |> assign(:color_hsl, hsl)
      |> assign(:color_modal_mode, :single)
      |> assign(:picker_anchor_id, picker_anchor_id)
      |> assign(:show_color_modal, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_global_color_modal", params, socket) do
    # Use default color or last used color
    color = Map.put_new(socket.assigns.color, :temperature, nil)
    hsl = rgb_to_hsl(color)
    picker_anchor_id = Map.get(params, "anchor", "add-mood-button")

    socket =
      socket
      |> assign(:color, color)
      # Store original color for cancel
      |> assign(:original_color, color)
      |> assign(:color_hsl, hsl)
      |> assign(:color_modal_mode, :all)
      |> assign(:picker_anchor_id, picker_anchor_id)
      |> assign(:show_color_modal, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_color_modal", _params, socket) do
    # Restore original color when canceling
    original_color = socket.assigns.original_color || socket.assigns.color
    hsl = rgb_to_hsl(original_color)

    socket =
      socket
      |> assign(:show_color_modal, false)
      |> assign(:color, original_color)
      |> assign(:color_hsl, hsl)
      |> assign(:picker_anchor_id, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("color_changed", %{"r" => r, "g" => g, "b" => b}, socket) do
    # When color wheel changes, clear temperature (using RGB mode)
    # Keep saturation at 100% and lightness at 50% for vibrant colors
    updated_color = Map.merge(socket.assigns.color, %{r: r, g: g, b: b, temperature: nil})
    hsl = rgb_to_hsl(updated_color)
    {:noreply, socket |> assign(:color, updated_color) |> assign(:color_hsl, hsl)}
  end

  @impl true
  def handle_event("update_color", params, socket) do
    # Handle both formats: %{"color" => %{"r" => "123"}} or direct params
    color_params = Map.get(params, "color", params)

    updated_color =
      socket.assigns.color
      |> Map.merge(atomize_color_params(color_params))

    # If temperature is being set, convert to RGB for preview
    updated_color =
      if Map.has_key?(updated_color, :temperature) && updated_color.temperature do
        {r, g, b} = kelvin_to_rgb(updated_color.temperature)
        Map.merge(updated_color, %{r: r, g: g, b: b})
      else
        updated_color
      end

    hsl = rgb_to_hsl(updated_color)
    {:noreply, socket |> assign(:color, updated_color) |> assign(:color_hsl, hsl)}
  end

  @impl true
  def handle_event("update_temperature", %{"temperature" => temp_str}, socket) do
    case Integer.parse(temp_str) do
      {temp, _} when temp >= 2200 and temp <= 6500 ->
        {r, g, b} = kelvin_to_rgb(temp)
        # When temperature is set, use temperature mode (ignore hue wheel)
        # Convert Kelvin to RGB for preview only, but use set_temp when applying
        updated_color = Map.merge(socket.assigns.color, %{temperature: temp, r: r, g: g, b: b})
        hsl = rgb_to_hsl(updated_color)
        {:noreply, socket |> assign(:color, updated_color) |> assign(:color_hsl, hsl)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_color_from_hex", params, socket) do
    raw_hex = params["hex"] || params["value"] || Map.values(params) |> List.first()

    case normalize_hex(raw_hex) do
      {:ok, hex} ->
        {r, g, b} = hex_to_rgb(hex)
        color = Map.merge(socket.assigns.color, %{r: r, g: g, b: b})
        hsl = rgb_to_hsl(color)
        {:noreply, socket |> assign(:color, color) |> assign(:color_hsl, hsl)}

      :error ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_color", _params, socket) do
    color = socket.assigns.color
    mode = socket.assigns.color_modal_mode

    case mode do
      :all ->
        bulbs = socket.assigns.bulbs
        {successful, failed} = apply_color_to_bulbs(bulbs, color)

        socket =
          socket
          |> put_flash(
            :info,
            "Color applied to #{length(successful)} light(s)#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
          )
          |> refresh_lights()
          |> assign(:show_color_modal, false)
          |> assign(:picker_anchor_id, nil)

        {:noreply, socket}

      :single ->
        if socket.assigns.selected_bulb do
          bulb = socket.assigns.selected_bulb
          result = apply_color_to_bulb(bulb, color)

          case result do
            {:ok, _bulb} ->
              socket =
                socket
                |> put_flash(:info, "Color applied to #{bulb.name || bulb.ip}")
                |> refresh_lights()
                |> assign(:selected_bulb, Lights.get_bulb!(bulb.id))
                |> assign(:show_color_modal, false)
                |> assign(:picker_anchor_id, nil)

              {:noreply, socket}

            {:error, _failed_bulb, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to set color: #{inspect(reason)}")}
          end
        else
          {:noreply, put_flash(socket, :error, "Please select a bulb first")}
        end
    end
  end

  @impl true
  def handle_event("set_all_color", _params, socket) do
    color = socket.assigns.color
    bulbs = socket.assigns.bulbs
    {successful, failed} = apply_color_to_bulbs(bulbs, color)

    socket =
      socket
      |> put_flash(
        :info,
        "Color applied to #{length(successful)} bulb(s)#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
      )
      |> refresh_lights()

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_light", %{"id" => id}, socket) do
    bulb = Lights.get_bulb!(id)

    # Get current status to determine new state
    case WizHome.get_status(bulb.ip) do
      {:ok, %{"result" => %{"state" => current_state}}} ->
        new_state = !current_state

        case WizHome.set_state(bulb.ip, new_state) do
          {:ok, _} ->
            socket =
              socket
              |> put_flash(:info, "Light #{if new_state, do: "turned on", else: "turned off"}")
              |> refresh_lights()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to toggle light: #{inspect(reason)}")}
        end

      {:error, _reason} ->
        # If we can't get status, try to turn it on
        case WizHome.set_state(bulb.ip, true) do
          {:ok, _} ->
            socket =
              socket
              |> put_flash(:info, "Light turned on")
              |> refresh_lights()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to toggle light: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("set_all_state", %{"state" => state_str}, socket) do
    state = state_str == "true"
    bulbs = socket.assigns.bulbs

    results =
      Enum.map(bulbs, fn bulb ->
        case WizHome.set_state(bulb.ip, state) do
          {:ok, _} -> {:ok, bulb}
          {:error, reason} -> {:error, bulb, reason}
        end
      end)

    {successful, failed} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _, _} -> false
      end)

    socket =
      socket
      |> put_flash(
        :info,
        "#{length(successful)} light(s) #{if state, do: "turned on", else: "turned off"}#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
      )
      |> refresh_lights()

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_preset_color", %{"color" => color_name}, socket) do
    color = preset_color(color_name)
    hsl = rgb_to_hsl(color)
    {:noreply, socket |> assign(:color, color) |> assign(:color_hsl, hsl)}
  end

  @impl true
  def handle_event("apply_mood", %{"color" => color_name}, socket) do
    color = preset_color(color_name)
    bulbs = socket.assigns.bulbs
    {successful, failed} = apply_color_to_bulbs(bulbs, color)
    hsl = rgb_to_hsl(color)

    socket =
      socket
      |> assign(:color, color)
      |> assign(:color_hsl, hsl)
      |> refresh_lights()
      |> put_flash(
        :info,
        "Mood applied to #{length(successful)} light(s)#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "update_bulb_brightness",
        %{"id" => id, "brightness" => brightness_raw},
        socket
      ) do
    case Integer.parse(brightness_raw) do
      {brightness, _} when brightness >= 10 and brightness <= 100 ->
        bulb = Lights.get_bulb!(id)
        color = bulb_color_payload(bulb, brightness)

        case apply_color_to_bulb(bulb, color) do
          {:ok, _updated_bulb} ->
            {:noreply, refresh_lights(socket)}

          {:error, _failed_bulb, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to update brightness: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # Helper functions

  defp atomize_color_params(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      case Integer.parse(value) do
        {int, _} -> Map.put(acc, String.to_existing_atom(key), int)
        :error -> acc
      end
    end)
  end

  defp hex_to_rgb(hex) when is_binary(hex) do
    hex = String.replace(hex, "#", "")
    {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
    {r, g, b}
  end

  defp normalize_hex(hex) when is_binary(hex) do
    parsed_hex =
      hex
      |> String.trim()
      |> String.trim_leading("#")
      |> String.upcase()

    if String.match?(parsed_hex, ~r/\A[0-9A-F]{6}\z/) do
      {:ok, parsed_hex}
    else
      :error
    end
  end

  defp normalize_hex(_), do: :error

  defp rgb_to_hex(%{r: r, g: g, b: b}) do
    [r, g, b]
    |> Enum.map(fn value -> value |> Integer.to_string(16) |> String.pad_leading(2, "0") end)
    |> Enum.join("")
    |> String.upcase()
  end

  defp refresh_lights(socket) do
    bulbs = Lights.list_bulbs()
    bulb_states = load_bulb_states(bulbs)

    socket
    |> assign(:bulbs, bulbs)
    |> assign(:bulb_states, bulb_states)
    |> assign(:all_lights_on, all_lights_on?(bulbs, bulb_states))
  end

  defp load_bulb_states(bulbs) do
    Enum.reduce(bulbs, %{}, fn bulb, acc ->
      Map.put(acc, bulb.id, bulb_on?(bulb))
    end)
  end

  defp all_lights_on?([], _states), do: false

  defp all_lights_on?(bulbs, states) do
    Enum.all?(bulbs, fn bulb -> Map.get(states, bulb.id, false) end)
  end

  defp bulb_on?(bulb) do
    case WizHome.get_status(bulb.ip) do
      {:ok, %{"result" => %{"state" => state}}} when is_boolean(state) -> state
      _ -> false
    end
  end

  defp apply_color_to_bulbs(bulbs, color) do
    results = Enum.map(bulbs, fn bulb -> apply_color_to_bulb(bulb, color) end)

    successful =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    failed =
      Enum.filter(results, fn
        {:error, _, _} -> true
        _ -> false
      end)

    {successful, failed}
  end

  defp apply_color_to_bulb(bulb, color) do
    result =
      if color.temperature do
        WizHome.set_temp(bulb.ip, color.temperature, color.brightness)
      else
        WizHome.set_rgb(bulb.ip, {color.r, color.g, color.b}, color.brightness)
      end

    case result do
      {:ok, _} ->
        case Lights.update_bulb_color(bulb, %{
               last_color_r: color.r,
               last_color_g: color.g,
               last_color_b: color.b,
               last_brightness: color.brightness,
               last_temperature: color.temperature
             }) do
          {:ok, updated_bulb} -> {:ok, updated_bulb}
          {:error, changeset} -> {:error, bulb, changeset}
        end

      {:error, reason} ->
        {:error, bulb, reason}
    end
  end

  defp bulb_color_payload(bulb, brightness) do
    cond do
      bulb.last_temperature ->
        {r, g, b} = kelvin_to_rgb(bulb.last_temperature)
        %{r: r, g: g, b: b, brightness: brightness, temperature: bulb.last_temperature}

      bulb.last_color_r && bulb.last_color_g && bulb.last_color_b ->
        %{
          r: bulb.last_color_r,
          g: bulb.last_color_g,
          b: bulb.last_color_b,
          brightness: brightness,
          temperature: nil
        }

      true ->
        %{r: 255, g: 255, b: 255, brightness: brightness, temperature: nil}
    end
  end

  defp bulb_color_style(bulb) do
    color = bulb_color_payload(bulb, bulb.last_brightness || 60)

    "background-color: rgb(#{color.r}, #{color.g}, #{color.b}); opacity: #{max(color.brightness, 25) / 100}"
  end

  defp mood_presets do
    [
      %{key: "deep_blue", label: "My mood 01", image: @mood_image_map.deep_blue},
      %{key: "soft_teal", label: "My mood 02", image: @mood_image_map.soft_teal},
      %{key: "cool_green", label: "My mood 03", image: @mood_image_map.cool_green},
      %{key: "muted_cyan", label: "My mood 04", image: @mood_image_map.muted_cyan},
      %{key: "warm_white", label: "My mood 05", image: @mood_image_map.warm_white},
      %{key: "pure_white", label: "My mood 06", image: @mood_image_map.pure_white}
    ]
  end

  defp rgb_to_hsl(%{r: r, g: g, b: b}) do
    r_norm = r / 255
    g_norm = g / 255
    b_norm = b / 255

    max = Enum.max([r_norm, g_norm, b_norm])
    min = Enum.min([r_norm, g_norm, b_norm])
    delta = max - min

    l = (max + min) / 2

    {h, s} =
      if delta == 0 do
        {0, 0}
      else
        s =
          if l < 0.5 do
            delta / (max + min)
          else
            delta / (2 - max - min)
          end

        h_raw =
          cond do
            r_norm == max -> (g_norm - b_norm) / delta
            g_norm == max -> (b_norm - r_norm) / delta + 2
            b_norm == max -> (r_norm - g_norm) / delta + 4
            true -> 0
          end

        # Normalize to 0-6 range
        h_raw = h_raw - trunc(h_raw / 6) * 6
        h = h_raw * 60
        h = if h < 0, do: h + 360, else: h

        {h, s * 100}
      end

    %{hue: h, saturation: s, lightness: l * 100}
  end

  # Preset colors optimized for coding/productivity
  # Deep Blue (Calm Focus)
  defp preset_color("deep_blue"), do: %{r: 0, g: 0, b: 139, brightness: 75, temperature: nil}
  # Soft Teal (Balanced Productivity)
  defp preset_color("soft_teal"), do: %{r: 64, g: 224, b: 208, brightness: 75, temperature: nil}
  # Cool Green (Refresh and Clarity)
  defp preset_color("cool_green"), do: %{r: 0, g: 128, b: 128, brightness: 75, temperature: nil}
  # Muted Cyan (Tech Zen Mode)
  defp preset_color("muted_cyan"), do: %{r: 0, g: 191, b: 255, brightness: 75, temperature: nil}
  # Warm White (Evening Wind Down)
  defp preset_color("warm_white"), do: %{r: 255, g: 244, b: 229, brightness: 75, temperature: nil}
  # Pure White
  defp preset_color("pure_white"), do: %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}
  defp preset_color(_), do: %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}

  # Convert Kelvin temperature to RGB
  # Based on the algorithm from Tanner Helland: http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
  defp kelvin_to_rgb(kelvin) when kelvin >= 2200 and kelvin <= 6500 do
    # Normalize temperature to 0-1 range
    temp = kelvin / 100.0

    # Calculate red
    r =
      cond do
        temp <= 66 ->
          255

        true ->
          red = temp - 60
          red = 329.698727446 * :math.pow(red, -0.1332047592)
          red = max(0, min(255, red))
          round(red)
      end

    # Calculate green
    g =
      cond do
        temp <= 66 ->
          green = temp
          green = 99.4708025861 * :math.log(green) - 161.1195681661
          green = max(0, min(255, green))
          round(green)

        true ->
          green = temp - 60
          green = 288.1221695283 * :math.pow(green, -0.0755148492)
          green = max(0, min(255, green))
          round(green)
      end

    # Calculate blue
    b =
      cond do
        temp >= 66 ->
          255

        temp <= 19 ->
          0

        true ->
          blue = temp - 10
          blue = 138.5177312231 * :math.log(blue) - 305.0447927307
          blue = max(0, min(255, blue))
          round(blue)
      end

    {r, g, b}
  end

  defp kelvin_to_rgb(_), do: {255, 255, 255}
end

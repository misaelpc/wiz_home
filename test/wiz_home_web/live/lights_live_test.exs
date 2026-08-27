defmodule WizHomeWeb.LightsLiveTest do
  use WizHomeWeb.ConnCase

  import Phoenix.LiveViewTest

  test "home is served at the root with the redesigned navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#home-top-nav")
    assert has_element?(view, "#nav-my-home")
    assert has_element?(view, "#nav-add-light")
    assert has_element?(view, "#toggle-all-lights")
    assert has_element?(view, "#mood-deep_blue", "Deep Blue")
    assert has_element?(view, "#mood-soft_teal", "Soft Teal")
    assert has_element?(view, "#mood-cool_green", "Cool Green")
    assert has_element?(view, "#mood-muted_cyan", "Muted Cyan")
    assert has_element?(view, "#mood-warm_white", "Warm White")
    assert has_element?(view, "#mood-pure_white", "Pure White")
    refute has_element?(view, "#add-bulb-form")
  end

  test "add light opens register under the same navigation", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#nav-add-light") |> render_click()
    assert_patch(view, ~p"/register")
    assert has_element?(view, "#home-top-nav")
    assert has_element?(view, "#add-bulb-form")
    refute has_element?(view, "#toggle-all-lights")
  end

  test "my home returns to the root from register", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    assert has_element?(view, "#home-top-nav")
    assert has_element?(view, "#add-bulb-form")

    view |> element("#nav-my-home") |> render_click()
    assert_patch(view, ~p"/")
    assert has_element?(view, "#toggle-all-lights")
  end

  test "legacy lights admin url redirects to root", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, "/lights/admin")
  end

  test "legacy lights register url redirects to /register", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/register"}}} = live(conn, "/lights/register")
  end
end

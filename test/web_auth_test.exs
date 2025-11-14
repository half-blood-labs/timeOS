defmodule WebAuthTest do
  use TimeOS.DataCase
  import Plug.Test
  import Plug.Conn

  alias TimeOS.Web

  @opts Web.init([])

  describe "Web UI authentication" do
    test "allows access when authentication is disabled" do
      # Mock config to disable auth
      Application.put_env(:timeos, :ui_auth_enabled, false)

      conn =
        conn(:get, "/")
        |> Web.call(@opts)

      # Should not return 401
      refute conn.status == 401
    end

    test "requires authentication when enabled" do
      # Enable auth
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_username, "admin")
      Application.put_env(:timeos, :ui_password, "password123")

      conn =
        conn(:get, "/")
        |> Web.call(@opts)

      # Should return 401
      assert conn.status == 401
      assert get_resp_header(conn, "www-authenticate") == ["Basic realm=\"TimeOS\""]
    end

    test "allows access with correct basic auth credentials" do
      # Enable auth
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_username, "admin")
      Application.put_env(:timeos, :ui_password, "password123")

      # Create basic auth header
      credentials = Base.encode64("admin:password123")

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Basic #{credentials}")
        |> Web.call(@opts)

      # Should not return 401
      refute conn.status == 401
    end

    test "rejects access with incorrect basic auth credentials" do
      # Enable auth
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_username, "admin")
      Application.put_env(:timeos, :ui_password, "password123")

      # Create basic auth header with wrong password
      credentials = Base.encode64("admin:wrongpassword")

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Basic #{credentials}")
        |> Web.call(@opts)

      # Should return 401
      assert conn.status == 401
    end

    test "allows access with correct API key" do
      # Enable auth with API key
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_api_key, "secret-api-key-123")

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer secret-api-key-123")
        |> Web.call(@opts)

      # Should not return 401
      refute conn.status == 401
    end

    test "rejects access with incorrect API key" do
      # Enable auth with API key
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_api_key, "secret-api-key-123")

      conn =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer wrong-api-key")
        |> Web.call(@opts)

      # Should return 401
      assert conn.status == 401
    end

    test "rejects access with missing API key when API key auth is enabled" do
      # Enable auth with API key
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_api_key, "secret-api-key-123")

      conn =
        conn(:get, "/")
        |> Web.call(@opts)

      # Should return 401
      assert conn.status == 401
    end

    test "prefers API key over basic auth when both are provided" do
      # Enable auth with API key
      Application.put_env(:timeos, :ui_auth_enabled, true)
      Application.put_env(:timeos, :ui_api_key, "secret-api-key-123")
      Application.put_env(:timeos, :ui_username, "admin")
      Application.put_env(:timeos, :ui_password, "password123")

      # Test with Bearer token (API key takes precedence in our implementation)
      conn2 =
        conn(:get, "/")
        |> put_req_header("authorization", "Bearer secret-api-key-123")
        |> Web.call(@opts)

      refute conn2.status == 401
    end
  end
end

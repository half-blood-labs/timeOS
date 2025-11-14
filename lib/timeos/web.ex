defmodule TimeOS.Web do
  @moduledoc """
  Web interface for TimeOS job monitoring.
  """

  use Plug.Router
  require Logger
  import Plug.Conn

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  def start do
    port = Application.get_env(:timeos, :ui_port, 4000)
    Logger.info("Starting TimeOS UI on port #{port}")
    Plug.Cowboy.http(__MODULE__, [], port: port)
  end

  get "/" do
    jobs = TimeOS.list_jobs(status: nil, limit: 1000)
    health = TimeOS.health_check()

    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>TimeOS - Job Monitor</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
          background: #f5f5f5;
          color: #333;
          line-height: 1.6;
        }
        .header {
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          padding: 2rem;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header h1 { font-size: 2rem; margin-bottom: 0.5rem; }
        .header p { opacity: 0.9; }
        .container {
          max-width: 1400px;
          margin: 2rem auto;
          padding: 0 1rem;
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
          gap: 1rem;
          margin-bottom: 2rem;
        }
        .stat-card {
          background: white;
          padding: 1.5rem;
          border-radius: 8px;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .stat-card h3 {
          font-size: 0.875rem;
          color: #666;
          text-transform: uppercase;
          margin-bottom: 0.5rem;
        }
        .stat-card .value {
          font-size: 2rem;
          font-weight: bold;
          color: #667eea;
        }
        .filters {
          background: white;
          padding: 1rem;
          border-radius: 8px;
          margin-bottom: 1rem;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .filters select, .filters button {
          padding: 0.5rem 1rem;
          border: 1px solid #ddd;
          border-radius: 4px;
          margin-right: 0.5rem;
          font-size: 0.875rem;
        }
        .filters button {
          background: #667eea;
          color: white;
          border: none;
          cursor: pointer;
        }
        .filters button:hover { background: #5568d3; }
        .jobs-table {
          background: white;
          border-radius: 8px;
          overflow: hidden;
          box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        table {
          width: 100%;
          border-collapse: collapse;
        }
        thead {
          background: #f8f9fa;
        }
        th {
          padding: 1rem;
          text-align: left;
          font-weight: 600;
          color: #666;
          font-size: 0.875rem;
          text-transform: uppercase;
        }
        td {
          padding: 1rem;
          border-top: 1px solid #eee;
        }
        tr:hover { background: #f8f9fa; }
        .status {
          display: inline-block;
          padding: 0.25rem 0.75rem;
          border-radius: 12px;
          font-size: 0.75rem;
          font-weight: 600;
          text-transform: uppercase;
        }
        .status.pending { background: #fff3cd; color: #856404; }
        .status.running { background: #d1ecf1; color: #0c5460; }
        .status.success { background: #d4edda; color: #155724; }
        .status.failed { background: #f8d7da; color: #721c24; }
        .status.dead { background: #f5c6cb; color: #721c24; }
        .priority {
          font-weight: bold;
          color: #667eea;
        }
        .job-id {
          font-family: monospace;
          font-size: 0.75rem;
          color: #666;
        }
        .timestamp {
          font-size: 0.875rem;
          color: #666;
        }
        .health-badge {
          display: inline-block;
          padding: 0.25rem 0.75rem;
          border-radius: 12px;
          font-size: 0.75rem;
          font-weight: 600;
          margin-left: 0.5rem;
        }
        .health-badge.healthy { background: #d4edda; color: #155724; }
        .health-badge.degraded { background: #fff3cd; color: #856404; }
        .health-badge.unhealthy { background: #f8d7da; color: #721c24; }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>TimeOS Job Monitor</h1>
        <p>Real-time job monitoring and management
          <span class="health-badge #{String.to_atom(to_string(health.status))}">
            #{String.capitalize(to_string(health.status))}
          </span>
        </p>
      </div>
      <div class="container">
        <div class="stats">
          <div class="stat-card">
            <h3>Pending Jobs</h3>
            <div class="value">#{health.metrics.pending_jobs}</div>
          </div>
          <div class="stat-card">
            <h3>Running Jobs</h3>
            <div class="value">#{health.metrics.running_jobs}</div>
          </div>
          <div class="stat-card">
            <h3>Failed Jobs</h3>
            <div class="value">#{health.metrics.failed_jobs}</div>
          </div>
          <div class="stat-card">
            <h3>Dead Letter Queue</h3>
            <div class="value">#{health.metrics.dead_letter_jobs}</div>
          </div>
          <div class="stat-card">
            <h3>Total Rules</h3>
            <div class="value">#{health.metrics.total_rules}</div>
          </div>
          <div class="stat-card">
            <h3>Enabled Rules</h3>
            <div class="value">#{health.metrics.enabled_rules}</div>
          </div>
        </div>
        <div class="filters">
          <select id="statusFilter" onchange="filterJobs()">
            <option value="">All Statuses</option>
            <option value="pending">Pending</option>
            <option value="running">Running</option>
            <option value="success">Success</option>
            <option value="failed">Failed</option>
            <option value="dead">Dead</option>
          </select>
          <button onclick="location.reload()">Refresh</button>
          <button onclick="autoRefresh()">Auto Refresh: <span id="autoRefreshStatus">Off</span></button>
        </div>
        <div class="jobs-table">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Status</th>
                <th>Priority</th>
                <th>Action</th>
                <th>Perform At</th>
                <th>Attempts</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              #{render_jobs(jobs)}
            </tbody>
          </table>
        </div>
      </div>
      <script>
        let autoRefreshInterval = null;
        function filterJobs() {
          const filter = document.getElementById('statusFilter').value;
          const rows = document.querySelectorAll('tbody tr');
          rows.forEach(row => {
            const status = row.querySelector('.status').textContent.toLowerCase();
            if (!filter || status === filter) {
              row.style.display = '';
            } else {
              row.style.display = 'none';
            }
          });
        }
        function autoRefresh() {
          if (autoRefreshInterval) {
            clearInterval(autoRefreshInterval);
            autoRefreshInterval = null;
            document.getElementById('autoRefreshStatus').textContent = 'Off';
          } else {
            autoRefreshInterval = setInterval(() => location.reload(), 5000);
            document.getElementById('autoRefreshStatus').textContent = 'On (5s)';
          }
        }
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  defp render_jobs(jobs) do
    jobs
    |> Enum.map(fn job ->
      status_class = String.downcase(to_string(job.status))
      perform_at = format_datetime(job.perform_at)
      error = if job.last_error, do: String.slice(job.last_error, 0, 50), else: ""
      action = get_in(job.args, ["action"]) || "N/A"

      """
      <tr>
        <td><div class="job-id">#{String.slice(job.id, 0, 8)}...</div></td>
        <td><span class="status #{status_class}">#{job.status}</span></td>
        <td><span class="priority">#{job.priority}</span></td>
        <td>#{action}</td>
        <td><div class="timestamp">#{perform_at}</div></td>
        <td>#{job.attempt_count}/#{job.max_attempts}</td>
        <td>#{error}</td>
      </tr>
      """
    end)
    |> Enum.join("\n")
  end

  defp format_datetime(dt) when is_nil(dt), do: "N/A"

  defp format_datetime(dt) do
    dt
    |> DateTime.to_naive()
    |> NaiveDateTime.to_string()
    |> String.slice(0, 19)
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end

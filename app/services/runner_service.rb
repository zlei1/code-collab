require "open3"
require "timeout"

class RunnerService
  TIMEOUT_SECONDS = 10

  def self.run(room)
    scaffold = Scaffolds::Catalog.find(room.template_key)
    raise "Unknown scaffold" unless scaffold

    RoomWorkspace.export_to_disk(room)
    workspace = RoomWorkspace.root_path(room)
    image = scaffold["image"]
    command = scaffold["run_cmd"]

    stdout = ""
    stderr = ""
    status = "failed"
    exit_code = nil
    pid = nil

    begin
      Timeout.timeout(TIMEOUT_SECONDS) do
        Open3.popen3(*docker_command(image, workspace, command)) do |stdin, out, err, wait_thr|
          pid = wait_thr.pid
          stdin.close

          out_thread = Thread.new { out.read }
          err_thread = Thread.new { err.read }
          stdout = out_thread.value.to_s
          stderr = err_thread.value.to_s

          process_status = wait_thr.value
          exit_code = process_status.exitstatus
          status = process_status.success? ? "succeeded" : "failed"
        end
      end
    ensure
      # Optional: keep workspace for debugging if needed, but usually cleanup
      # RoomWorkspace.cleanup(room)
    end

    { stdout: stdout, stderr: stderr, status: status, exit_code: exit_code }
  rescue Timeout::Error
    terminate_process(pid)
    { stdout: "", stderr: "Execution timed out after #{TIMEOUT_SECONDS}s", status: "failed", exit_code: nil }
  rescue Errno::ENOENT => e
    { stdout: "", stderr: "Runner error: #{e.message}", status: "failed", exit_code: nil }
  end

  def self.terminate_process(pid)
    return unless pid
    Process.kill("TERM", pid)
    sleep 0.2
    Process.kill("KILL", pid)
  rescue StandardError
    nil
  end

  def self.docker_command(image, workspace, command)
    [
      "docker", "run", "--rm",
      "--network", "none",
      "--cpus=1",
      "--memory=512m",
      "--pids-limit=128",
      "-v", "#{workspace}:/workspace",
      "-w", "/workspace",
      image,
      "sh", "-lc", command
    ]
  end
end

class RoomRunJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = RoomRun.find(run_id)
    run.update!(status: "running", started_at: Time.current)
    ActionCable.server.broadcast(RoomRunChannel.stream_name(run.room), { type: "status", run_id: run.id, status: run.status })

    result = RunnerService.run(run.room)

    run.update!(
      status: result[:status],
      stdout: result[:stdout],
      stderr: result[:stderr],
      exit_code: result[:exit_code],
      finished_at: Time.current
    )

    ActionCable.server.broadcast(RoomRunChannel.stream_name(run.room), {
      type: "result",
      run_id: run.id,
      status: run.status,
      stdout: run.stdout,
      stderr: run.stderr,
      exit_code: run.exit_code
    })
  rescue StandardError => e
    run.update!(status: "failed", stderr: e.message, finished_at: Time.current) if run
    ActionCable.server.broadcast(RoomRunChannel.stream_name(run.room), {
      type: "result",
      run_id: run.id,
      status: "failed",
      stderr: e.message
    }) if run
  end
end

namespace :room_ot do
  desc "Start the Redis-backed OT worker for a shard (set OT_STREAM_SHARD_ID)"
  task worker: :environment do
    RoomOTWorker.run
  end
end

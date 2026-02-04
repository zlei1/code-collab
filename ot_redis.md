# Redis OT Design

## Goals
- Multi-machine support with per-room serialization and cross-room parallelism.
- Shared state and history in Redis.
- History compaction with forced resync when history is truncated.

## Redis Keys
- `ot:state:{room_id}:{path}` hash
  - `doc`: current document
  - `rev`: absolute revision
  - `base_rev`: base revision for history list
  - `last_id`: last processed stream entry (optional)
- `ot:history:{room_id}:{path}` list
  - JSON entries with `operation` and `selection`
- `ot:clients:{room_id}:{path}` hash
  - `{client_id: {name?, selection?, seen_at}}`
- `ot:ops:{shard}` stream
  - fields: `scope`, `room_id`, `path`, `client_id`, `revision`, `operation`, `selection`
- `ot:ops:{shard}:checkpoint` string
  - last processed stream id for worker

## Presence (Redis)
- Key: `presence:room:{room_id}` (hash: client_id -> payload)
- Fields: `user_id`, `label`, `email`, `has_media`, `seen_at`
- TTL cleanup: `ROOM_PRESENCE_TTL` (seconds, default 300)

## Sharding
- `OT_STREAM_SHARDS` controls total stream shards (default `1`).
- `shard = crc32("#{room_id}:#{path}") % OT_STREAM_SHARDS`.
- Each worker handles a single shard via `OT_STREAM_SHARD_ID`.

## Flow
1. Channel enqueues operations into the shard stream.
2. Worker consumes stream entries per shard.
3. Worker applies OT and updates:
   - `state` (doc/rev/base_rev)
   - `history` (append)
4. Worker broadcasts `operation` and `ack` to clients.
5. Clients update their local editor state.

## History Compaction
- `OT_HISTORY_MAX` caps in-memory history length (default `5000`).
- When `operations.length > OT_HISTORY_MAX`:
  - Worker compacts server history and advances `base_rev`.
  - Redis `history` list is deleted.
  - Worker broadcasts `{type: "resync"}` to force client resync.
- Clients receiving `resync` call `resync` to fetch fresh `doc` and `revision`.

## Global Collaboration
- Global collaboration uses `room_id=0` and `path=__global__`.
- `scope=global` in stream entries and broadcasts to `CollaborationChannel::STREAM_NAME`.

## Operational Notes
- Start workers: `bin/rails room_ot:worker` with shard env vars.
- Web and workers must use the same Redis and shard counts.
- Consider monitoring stream lag and history size.

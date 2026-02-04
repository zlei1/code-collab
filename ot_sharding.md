# OT Sharding

## Why Sharding
OT requires **per-room serial processing** but allows **cross-room parallelism**.
Sharding maps each `room_id:path` to a shard so only one worker processes that room's operations.

## How It Works
- `shard = crc32("#{room_id}:#{path}") % OT_STREAM_SHARDS`
- Stream key: `ot:ops:{shard}`
- Worker processes one shard via `OT_STREAM_SHARD_ID`.

## Env Vars
- `OT_STREAM_SHARDS`: total shard count. All web + worker processes must share the same value.
- `OT_STREAM_SHARD_ID`: the shard index this worker handles. `0 <= id < OT_STREAM_SHARDS`.

## Example (single shard)
- `OT_STREAM_SHARDS=1` means **all rooms go to shard 0**.
- `OT_STREAM_SHARD_ID=0` starts the only worker needed in this mode.

## Example (16 shards)
- `OT_STREAM_SHARDS=16` means shards are `0..15`.
- Start 16 workers with `OT_STREAM_SHARD_ID=0..15` (or a subset if you want less capacity).

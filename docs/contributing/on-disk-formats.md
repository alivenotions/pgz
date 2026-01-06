# On-Disk Formats

All formats are **stable v1** — changes require migration code.

## Common Rules

- All I/O is 4KiB aligned
- Little-endian byte order
- CRC32C (Castagnoli) for checksums
- Zero-padding to alignment boundary

## vLog Record

```
┌──────────┬───────────┬─────────────────┬────────────────────┐
│ len: u32 │ crc32c: u32 │ payload: bytes │ zero-pad → 4KiB  │
└──────────┴───────────┴─────────────────┴────────────────────┘
```

| Field | Size | Description |
|-------|------|-------------|
| len | 4 bytes | Payload length (not including header/padding) |
| crc32c | 4 bytes | Checksum of payload only |
| payload | variable | The actual value data |
| padding | variable | Zeros to reach 4KiB boundary |

## SSTable Block

```
┌──────────────┬───────────┬────────────────────┬───────────┬────────────┐
│ block_len: u32 │ count: u32 │ entries...       │ crc32c: u32 │ pad→4KiB │
└──────────────┴───────────┴────────────────────┴───────────┴────────────┘
```

### Entry Format

```
┌────────────┬─────────┬───────────────────────────┬────────────┐
│ k_len: u16 │ key     │ vptr (seg:4 + off:8 + len:4) │ epoch: u32 │
└────────────┴─────────┴───────────────────────────┴────────────┘
```

Total: 2 + key_len + 16 + 4 = 22 + key_len bytes per entry

## Fence Index

```
┌─────────────────────────────────────────────────┬───────────┐
│ sorted array of (first_key, block_offset: u64)  │ crc32c    │
└─────────────────────────────────────────────────┴───────────┘
```

## Superblock

Two copies at fixed offsets (0 and 4096) for atomic updates.

```
┌────────────┬────────────┬──────────────┬─────────────────┬────────────┬───────────┐
│ magic: u32 │ version: u32 │ sequence: u64 │ manifest_off: u64 │ epoch: u64 │ crc32c: u32 │
└────────────┴────────────┴──────────────┴─────────────────┴────────────┴───────────┘
```

- Magic: `0x50475A53` ("PGZS")
- Sequence: higher = newer (for picking valid copy)

## ValuePointer

```
┌───────────┬────────────┬──────────┐
│ seg: u32  │ offset: u64 │ len: u32 │
└───────────┴────────────┴──────────┘
```

Total: 16 bytes

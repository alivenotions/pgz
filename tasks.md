# SSD-First Storage Layer Implementation Tasks

## Phase 1: Foundation & Core Storage Primitives

### 1.1 Project Infrastructure
- [ ] Set up testing framework in Zig
- [ ] Configure build system for multiple modules
  - [ ] Cross-platform build configuration
  - [ ] Platform-specific compilation flags
- [ ] Add benchmark harness infrastructure
- [ ] Set up continuous integration
  - [ ] CI for Linux (GitHub Actions)
  - [ ] CI for macOS (GitHub Actions)
  - [ ] Run tests on both platforms
- [ ] Create development documentation
  - [ ] Platform-specific setup instructions

### 1.2 Core Data Structures
- [ ] Implement Result type for error handling
- [ ] Implement arena allocator for temporary allocations
- [ ] Create buffer management utilities
- [ ] Implement comparison functions for keys
- [ ] Add serialization/deserialization helpers

### 1.3 MemTable Implementation
- [ ] Design MemTable interface
- [ ] Implement skip list data structure
  - [ ] Skip list node structure
  - [ ] Insert operation
  - [ ] Search operation
  - [ ] Iteration support
- [ ] Add MemTable size tracking
- [ ] Implement MemTable snapshot for consistent reads
- [ ] Add memory limit enforcement
- [ ] Write unit tests for MemTable operations

### 1.4 SSTable Format Design
- [ ] Define SSTable file format specification
- [ ] Design data block format
  - [ ] Block header structure
  - [ ] Key-value pair encoding
  - [ ] Compression integration points
- [ ] Design index block format
  - [ ] Sparse index structure
  - [ ] Block offset table
- [ ] Design footer format (metadata)
  - [ ] File magic number
  - [ ] Version information
  - [ ] Index block offset
  - [ ] Checksum
- [ ] Document wire format

### 1.5 SSTable Writer
- [ ] Implement SSTableBuilder
  - [ ] Add key-value pairs
  - [ ] Build data blocks (16KB-64KB target)
  - [ ] Build index blocks
  - [ ] Write footer
- [ ] Add compression support (LZ4)
  - [ ] Integrate LZ4 library or implement compression
  - [ ] Compress data blocks
  - [ ] Store compression metadata
- [ ] Implement block checksums (xxHash or CRC32C)
- [ ] Add direct I/O support
- [ ] Handle file sync/flush
- [ ] Write unit tests for SSTable writing

### 1.6 SSTable Reader
- [ ] Implement SSTable file handle management
- [ ] Parse SSTable footer
- [ ] Read and cache index block
- [ ] Implement block reader
  - [ ] Read block from file
  - [ ] Verify checksum
  - [ ] Decompress block
- [ ] Implement point lookup (Get)
  - [ ] Index block search
  - [ ] Data block search
  - [ ] Key comparison
- [ ] Implement range scan iterator
  - [ ] Seek to start key
  - [ ] Block-by-block iteration
  - [ ] Cross-block iteration
- [ ] Add read caching hooks
- [ ] Write unit tests for SSTable reading

### 1.7 Write-Ahead Log (WAL)
- [ ] Define WAL record format
  - [ ] Record header (LSN, checksum, length)
  - [ ] Record payload (operation type, key, value)
  - [ ] Transaction markers (BEGIN, COMMIT, ABORT)
- [ ] Implement WAL writer
  - [ ] Append records
  - [ ] Batch writes before fsync
  - [ ] Group commit optimization
- [ ] Implement WAL reader
  - [ ] Sequential read
  - [ ] Record validation
  - [ ] Parse records
- [ ] Add WAL rotation logic
  - [ ] Create new segment files
  - [ ] Archive old segments
- [ ] Implement crash recovery from WAL
  - [ ] Replay WAL records
  - [ ] Rebuild MemTable
  - [ ] Handle partial writes
- [ ] Write unit tests for WAL operations
- [ ] Write crash recovery tests

## Phase 2: LSM Engine Core

### 2.1 LSM Storage Engine Structure
- [ ] Define StorageEngine interface
  - [ ] Put(key, value)
  - [ ] Get(key)
  - [ ] Delete(key)
  - [ ] Scan(start_key, end_key)
- [ ] Implement LSM-tree manager
  - [ ] Manage MemTable instances
  - [ ] Track SSTable levels (L0-L6)
  - [ ] Metadata persistence
- [ ] Add manifest file for metadata
  - [ ] Current version
  - [ ] List of SSTables per level
  - [ ] WAL file references
  - [ ] Next file number
- [ ] Implement manifest operations (read, write, recover)

### 2.2 Write Path
- [ ] Implement Put operation
  - [ ] Write to WAL
  - [ ] Insert into MemTable
  - [ ] Check MemTable size threshold
  - [ ] Trigger flush if needed
- [ ] Implement Delete operation (tombstones)
  - [ ] Write tombstone to WAL
  - [ ] Insert tombstone into MemTable
- [ ] Implement MemTable flush
  - [ ] Freeze current MemTable
  - [ ] Create new active MemTable
  - [ ] Write MemTable to L0 SSTable
  - [ ] Update manifest
  - [ ] Delete corresponding WAL segment
- [ ] Add background flush queue
- [ ] Write unit tests for write path

### 2.3 Read Path
- [ ] Implement Get operation
  - [ ] Check active MemTable
  - [ ] Check frozen MemTables
  - [ ] Search L0 SSTables (newest first)
  - [ ] Search L1-L6 (binary search per level)
  - [ ] Return most recent version
- [ ] Implement Scan operation
  - [ ] Merge iterators from all sources
  - [ ] MemTable iterator
  - [ ] SSTable iterators
  - [ ] Multi-way merge with heap
  - [ ] Handle tombstones
- [ ] Add read-path optimizations
  - [ ] Early termination on found key
  - [ ] Skip deleted keys
- [ ] Write unit tests for read path

### 2.4 Compaction Foundation
- [ ] Design compaction algorithm (leveled compaction)
  - [ ] Calculate level sizes and triggers
  - [ ] Select SSTables for compaction
  - [ ] Merge algorithm
- [ ] Implement compaction scoring
  - [ ] Score each level
  - [ ] Priority queue for compaction jobs
- [ ] Implement manual compaction trigger
- [ ] Add compaction job structure
  - [ ] Input SSTables
  - [ ] Output level
  - [ ] Key range
- [ ] Write unit tests for compaction selection

### 2.5 Compaction Execution
- [ ] Implement SSTable merge
  - [ ] Multi-way merge of sorted SSTables
  - [ ] Drop older versions (MVCC aware)
  - [ ] Remove expired tombstones
  - [ ] Generate output SSTables
- [ ] Add compaction worker thread
  - [ ] Background thread pool
  - [ ] Job queue
  - [ ] Coordinate with writes
- [ ] Implement version management during compaction
  - [ ] Atomic metadata updates
  - [ ] Keep old SSTables until compaction completes
  - [ ] Clean up obsolete SSTables
- [ ] Add compaction throttling (rate limiting)
- [ ] Write integration tests for compaction

### 2.6 Bloom Filters
- [ ] Implement Bloom filter data structure
  - [ ] Bit array
  - [ ] Hash functions (2-3 functions)
  - [ ] Insert operation
  - [ ] Query operation
- [ ] Add Bloom filter to SSTable format
  - [ ] Store in SSTable footer or separate block
  - [ ] Configure false positive rate (1%)
- [ ] Build Bloom filter during SSTable creation
- [ ] Use Bloom filter in Get operation
- [ ] Write unit tests for Bloom filters
- [ ] Benchmark Bloom filter effectiveness

## Phase 3: Buffer Pool & I/O

### 3.1 Block Cache
- [ ] Design cache interface
  - [ ] Get block
  - [ ] Put block
  - [ ] Evict policy
- [ ] Implement LRU cache
  - [ ] Hash table for lookup
  - [ ] Doubly-linked list for LRU ordering
  - [ ] Thread-safe operations (mutex/RWLock)
- [ ] Add cache statistics
  - [ ] Hit rate
  - [ ] Miss rate
  - [ ] Eviction count
- [ ] Integrate cache with SSTable reader
- [ ] Add cache size limits and enforcement
- [ ] Write unit tests for block cache

### 3.2 Async I/O Layer (Cross-Platform)
- [ ] Design cross-platform I/O abstraction layer
  - [ ] Common interface for async read/write
  - [ ] Platform detection (comptime in Zig)
  - [ ] Feature flags for platform-specific code
- [ ] Implement file handle abstraction
  - [ ] Platform-specific direct I/O flags (O_DIRECT/F_NOCACHE)
  - [ ] Aligned buffer allocation (posix_memalign)
  - [ ] File metadata tracking
- [ ] **Linux Implementation (io_uring)**
  - [ ] Research io_uring in Zig (liburing bindings or native)
  - [ ] Initialize io_uring instance
  - [ ] Implement async read operation
    - [ ] Submit io_uring read request (SQE)
    - [ ] Handle completion (CQE)
    - [ ] Error handling
  - [ ] Implement async write operation
    - [ ] Submit io_uring write request
    - [ ] Handle completion
    - [ ] fsync support (IORING_OP_FSYNC)
  - [ ] Add I/O batching
    - [ ] Batch multiple I/Os in one submission
    - [ ] Process completions in batch
  - [ ] Tune io_uring parameters (queue depth, flags)
- [ ] **macOS Implementation (kqueue + AIO)**
  - [ ] Research kqueue in Zig
  - [ ] Initialize kqueue instance
  - [ ] Implement async read with POSIX AIO
    - [ ] Submit aio_read request
    - [ ] Monitor completion via kqueue (EVFILT_READ)
    - [ ] Handle completion
  - [ ] Implement async write with POSIX AIO
    - [ ] Submit aio_write request
    - [ ] Monitor completion via kqueue (EVFILT_WRITE)
    - [ ] fsync support (aio_fsync or fcntl F_FULLFSYNC)
  - [ ] Add I/O batching with lio_listio
  - [ ] Handle F_NOCACHE for direct I/O semantics
- [ ] **Fallback Implementation (POSIX AIO)**
  - [ ] Implement using standard POSIX aio
  - [ ] Thread pool for completion handling
  - [ ] Basic batching support
- [ ] Write benchmarks for I/O layer
  - [ ] Compare io_uring vs kqueue vs POSIX AIO
  - [ ] Test on both Linux and macOS
  - [ ] Measure throughput and latency
  - [ ] Test with different queue depths

### 3.3 File Management
- [ ] Implement file naming scheme
  - [ ] SSTable files: {number}.sst
  - [ ] WAL files: {number}.wal
  - [ ] Manifest: MANIFEST-{number}
  - [ ] Lock file: LOCK
- [ ] Add file operations
  - [ ] Create file
  - [ ] Delete file
  - [ ] Rename file (atomic)
  - [ ] List files by pattern
- [ ] Implement file size tracking
- [ ] Add disk space monitoring
- [ ] Implement file cleanup (delete obsolete files)

## Phase 4: MVCC & Transaction Support

### 4.1 Transaction ID Management
- [ ] Design transaction ID (XID) structure
  - [ ] 64-bit counter
  - [ ] Overflow handling
- [ ] Implement XID allocation
  - [ ] Atomic counter
  - [ ] XID wraparound detection
- [ ] Add transaction status tracking
  - [ ] In-progress transactions
  - [ ] Committed transactions
  - [ ] Aborted transactions
- [ ] Implement transaction manager
  - [ ] Begin transaction
  - [ ] Commit transaction
  - [ ] Abort transaction

### 4.2 Tuple Versioning
- [ ] Define tuple header format
  - [ ] xmin (creating XID)
  - [ ] xmax (deleting XID)
  - [ ] Flags (committed, deleted, etc.)
- [ ] Extend MemTable to store tuple versions
- [ ] Extend SSTable format for MVCC data
- [ ] Implement multi-version storage in LSM
  - [ ] Keep multiple versions during compaction
  - [ ] Respect snapshot visibility rules

### 4.3 Snapshot Isolation
- [ ] Implement snapshot data structure
  - [ ] Snapshot XID
  - [ ] Active transaction list
- [ ] Add snapshot acquisition (on BEGIN)
- [ ] Implement visibility check
  - [ ] Tuple visible to snapshot?
  - [ ] Handle in-progress transactions
  - [ ] Handle committed/aborted transactions
- [ ] Integrate visibility checks with read path
  - [ ] Filter invisible tuples in Get
  - [ ] Filter invisible tuples in Scan
- [ ] Write unit tests for snapshot isolation

### 4.4 Garbage Collection
- [ ] Design vacuum policy
  - [ ] Determine safe garbage collection point
  - [ ] Track oldest active snapshot
- [ ] Implement tuple expiration logic
  - [ ] Check if old version is visible to any snapshot
  - [ ] Mark as garbage
- [ ] Integrate garbage collection with compaction
  - [ ] Remove expired tuples during compaction
  - [ ] Remove expired tombstones
- [ ] Add manual VACUUM command
- [ ] Add auto-vacuum background worker
- [ ] Write tests for garbage collection

## Phase 5: Query Engine Foundation

### 5.1 Table Schema
- [ ] Define column data types
  - [ ] INTEGER (32-bit, 64-bit)
  - [ ] BOOLEAN
  - [ ] TEXT/VARCHAR
  - [ ] FLOAT/DOUBLE
  - [ ] TIMESTAMP
- [ ] Implement schema definition structure
  - [ ] Table name
  - [ ] Column definitions (name, type, constraints)
  - [ ] Primary key
- [ ] Add schema encoding/decoding
- [ ] Store schemas in system catalog (in LSM)

### 5.2 Tuple Format
- [ ] Design tuple layout
  - [ ] MVCC header
  - [ ] Null bitmap
  - [ ] Fixed-length fields
  - [ ] Variable-length field offsets
  - [ ] Variable-length field data
- [ ] Implement tuple serialization
- [ ] Implement tuple deserialization
- [ ] Add tuple accessor methods (get column value)
- [ ] Write unit tests for tuple operations

### 5.3 System Catalog
- [ ] Define system tables
  - [ ] pg_class (tables)
  - [ ] pg_attribute (columns)
  - [ ] pg_index (indexes)
  - [ ] pg_type (data types)
- [ ] Implement catalog initialization
  - [ ] Bootstrap catalog on first run
  - [ ] Create system tables
- [ ] Add catalog operations
  - [ ] Create table
  - [ ] Drop table
  - [ ] Lookup table by name
  - [ ] List all tables
- [ ] Cache catalog in memory
- [ ] Write tests for catalog operations

### 5.4 Basic SQL Parser Integration
- [ ] Evaluate SQL parser options
  - [ ] pg_query (C library with Zig bindings)
  - [ ] Custom parser (if needed)
- [ ] Integrate parser library
- [ ] Parse CREATE TABLE statement
- [ ] Parse INSERT statement
- [ ] Parse SELECT statement (simple)
- [ ] Parse UPDATE statement
- [ ] Parse DELETE statement
- [ ] Generate Abstract Syntax Tree (AST)
- [ ] Write tests for parser integration

### 5.5 Simple Query Executor
- [ ] Implement table scan operator
  - [ ] Open table
  - [ ] Iterate tuples
  - [ ] Apply predicate filter
- [ ] Implement INSERT executor
  - [ ] Generate new tuple
  - [ ] Assign ROWID/XID
  - [ ] Write to storage engine
- [ ] Implement DELETE executor
  - [ ] Find tuples matching condition
  - [ ] Write tombstones
- [ ] Implement UPDATE executor
  - [ ] Find tuples (scan)
  - [ ] Write new versions
  - [ ] Mark old versions deleted
- [ ] Implement simple SELECT executor
  - [ ] Scan table
  - [ ] Apply WHERE filter
  - [ ] Project columns
  - [ ] Return result set
- [ ] Write integration tests for basic queries

## Phase 6: Indexing

### 6.1 Primary Index
- [ ] Design primary key storage
  - [ ] Use table's LSM tree
  - [ ] Cluster by primary key
- [ ] Implement primary key uniqueness check
- [ ] Add primary key constraint validation
- [ ] Optimize queries using primary key
  - [ ] Point lookups
  - [ ] Range scans

### 6.2 Secondary Index Structure
- [ ] Design secondary index storage
  - [ ] Separate LSM tree per index
  - [ ] Index key → Primary key mapping
- [ ] Define index metadata
  - [ ] Index name
  - [ ] Indexed columns
  - [ ] Index type (B-tree-like via LSM)
- [ ] Implement index creation
  - [ ] Scan base table
  - [ ] Build index entries
  - [ ] Write to index LSM tree
- [ ] Store index metadata in catalog

### 6.3 Index Maintenance
- [ ] Update indexes on INSERT
  - [ ] Extract indexed columns
  - [ ] Write to index LSM trees
- [ ] Update indexes on DELETE
  - [ ] Write tombstones to indexes
- [ ] Update indexes on UPDATE
  - [ ] Delete old index entries
  - [ ] Insert new index entries
- [ ] Handle index corruption detection
- [ ] Implement REINDEX command

### 6.4 Index Usage in Queries
- [ ] Implement index scan operator
  - [ ] Seek to start key in index
  - [ ] Scan index LSM tree
  - [ ] Fetch tuples via primary key
- [ ] Add index selection in planner
  - [ ] Analyze WHERE clause
  - [ ] Choose best index
  - [ ] Cost estimation
- [ ] Optimize index-only scans (if possible)
- [ ] Write tests for index queries

## Phase 7: Postgres Wire Protocol

### 7.1 Connection Handling
- [ ] Implement TCP server
  - [ ] Listen on port (default 5432)
  - [ ] Accept connections
  - [ ] Handle multiple clients
- [ ] Implement connection state machine
  - [ ] Startup
  - [ ] Authentication
  - [ ] Ready for query
  - [ ] Query execution
  - [ ] Termination
- [ ] Add connection pooling (optional)

### 7.2 Protocol Messages
- [ ] Implement message framing
  - [ ] Message type (1 byte)
  - [ ] Message length (4 bytes)
  - [ ] Message payload
- [ ] Implement startup message handling
  - [ ] Parse client parameters
  - [ ] Protocol version negotiation
- [ ] Implement authentication messages
  - [ ] AuthenticationOk
  - [ ] AuthenticationMD5Password
  - [ ] PasswordMessage
- [ ] Implement query messages
  - [ ] Query (simple query)
  - [ ] Parse (prepared statement)
  - [ ] Bind
  - [ ] Execute
  - [ ] Describe
- [ ] Implement response messages
  - [ ] RowDescription
  - [ ] DataRow
  - [ ] CommandComplete
  - [ ] ReadyForQuery
  - [ ] ErrorResponse

### 7.3 Authentication
- [ ] Implement MD5 authentication
  - [ ] Generate salt
  - [ ] Verify MD5 hash
  - [ ] User database (simple file or table)
- [ ] Add clear text password option (dev only)
- [ ] Plan for SCRAM-SHA-256 (future)

### 7.4 Query Processing Pipeline
- [ ] Implement simple query protocol
  - [ ] Receive Query message
  - [ ] Parse SQL
  - [ ] Execute query
  - [ ] Send RowDescription
  - [ ] Send DataRow(s)
  - [ ] Send CommandComplete
- [ ] Implement extended query protocol
  - [ ] Parse → Bind → Execute flow
  - [ ] Named prepared statements
  - [ ] Parameter binding
- [ ] Add error handling and reporting
  - [ ] SQL errors
  - [ ] Protocol errors
  - [ ] Format ErrorResponse messages

### 7.5 Result Formatting
- [ ] Implement text format encoding
  - [ ] Integer to string
  - [ ] Float to string
  - [ ] Boolean to string
  - [ ] Timestamp to string
- [ ] Implement binary format (optional)
- [ ] Handle NULL values
- [ ] Add COPY protocol support (future)

## Phase 8: Query Planning & Optimization

### 8.1 Query Planner
- [ ] Implement logical plan generation
  - [ ] Scan operators
  - [ ] Filter (WHERE)
  - [ ] Project (SELECT columns)
  - [ ] Join operators
  - [ ] Aggregate operators
- [ ] Implement physical plan generation
  - [ ] SeqScan
  - [ ] IndexScan
  - [ ] NestedLoopJoin
  - [ ] HashJoin
  - [ ] HashAggregate
- [ ] Add plan optimization rules
  - [ ] Predicate pushdown
  - [ ] Projection pushdown
  - [ ] Join reordering

### 8.2 Cost Model
- [ ] Define cost parameters
  - [ ] Sequential I/O cost (low for SSD)
  - [ ] Random I/O cost (very low for SSD)
  - [ ] CPU cost
  - [ ] Memory cost
- [ ] Implement table statistics
  - [ ] Row count
  - [ ] Average row size
  - [ ] Data size
- [ ] Implement index statistics
  - [ ] Cardinality
  - [ ] Selectivity
- [ ] Implement cost estimation
  - [ ] Scan cost
  - [ ] Index scan cost
  - [ ] Join cost
- [ ] Tune cost model for SSD characteristics

### 8.3 Join Algorithms
- [ ] Implement nested loop join
  - [ ] Outer loop
  - [ ] Inner loop (scan or index lookup)
- [ ] Implement hash join
  - [ ] Build hash table
  - [ ] Probe hash table
  - [ ] Handle large inputs (spill to disk)
- [ ] Implement merge join (optional)
- [ ] Write tests for join operators

### 8.4 Aggregation
- [ ] Implement hash aggregation
  - [ ] Build hash table of groups
  - [ ] Compute aggregate functions (SUM, COUNT, AVG, MIN, MAX)
  - [ ] Output results
- [ ] Implement sort-based aggregation (optional)
- [ ] Support GROUP BY
- [ ] Support HAVING
- [ ] Write tests for aggregation

## Phase 9: Advanced Features

### 9.1 Transaction Commands
- [ ] Implement BEGIN command
- [ ] Implement COMMIT command
- [ ] Implement ROLLBACK command
- [ ] Add savepoints (SAVEPOINT, ROLLBACK TO)
- [ ] Test transaction scenarios
  - [ ] Read committed isolation
  - [ ] Repeatable read isolation
  - [ ] Serializable isolation (future)

### 9.2 Write-Ahead Log Enhancements
- [ ] Implement WAL archiving
- [ ] Add point-in-time recovery (PITR)
- [ ] Implement WAL compression
- [ ] Add WAL integrity checking

### 9.3 Crash Recovery
- [ ] Implement recovery manager
  - [ ] Detect incomplete shutdown
  - [ ] Replay WAL from checkpoint
  - [ ] Rebuild in-memory state
- [ ] Add checkpointing
  - [ ] Flush all dirty pages
  - [ ] Record checkpoint in WAL
  - [ ] Truncate old WAL segments
- [ ] Write crash recovery tests
  - [ ] Simulate crashes at various points
  - [ ] Verify data integrity after recovery

### 9.4 Concurrency Control
- [ ] Implement lock manager
  - [ ] Table-level locks
  - [ ] Row-level locks (optional)
  - [ ] Deadlock detection
- [ ] Add lock modes
  - [ ] Shared (S)
  - [ ] Exclusive (X)
  - [ ] Intent locks (IS, IX)
- [ ] Integrate locks with transactions
- [ ] Test concurrent workloads

## Phase 10: Performance Optimization

### 10.1 SSD-Specific Tuning
- [ ] Tune block sizes
  - [ ] Benchmark 4KB vs 16KB vs 64KB
  - [ ] Optimize for target SSD
- [ ] Optimize alignment
  - [ ] Align writes to SSD pages
  - [ ] Verify alignment in I/O layer
- [ ] Tune compaction parameters
  - [ ] Level size multipliers
  - [ ] Compaction trigger thresholds
  - [ ] Parallelism settings
- [ ] Benchmark write amplification
  - [ ] Measure bytes written vs bytes inserted
  - [ ] Target < 10x amplification

### 10.2 Parallelism
- [ ] Add parallel query execution
  - [ ] Parallel scans
  - [ ] Parallel joins
  - [ ] Parallel aggregation
- [ ] Implement parallel compaction
  - [ ] Multiple compaction threads
  - [ ] Partition key ranges
- [ ] Add parallel WAL replay (recovery)

### 10.3 Benchmarking
- [ ] Set up standard benchmarks
  - [ ] YCSB (Yahoo Cloud Serving Benchmark)
  - [ ] TPC-C (simplified)
  - [ ] Custom workloads
- [ ] Benchmark vs Postgres
  - [ ] Write throughput
  - [ ] Read latency
  - [ ] Mixed workloads
- [ ] **Cross-Platform Performance Testing**
  - [ ] Run benchmarks on Linux (io_uring)
  - [ ] Run benchmarks on macOS (kqueue)
  - [ ] Compare performance across platforms
  - [ ] Test on different SSD types (NVMe vs SATA)
  - [ ] Verify consistent behavior across platforms
- [ ] Profile hot paths
  - [ ] CPU profiling (perf on Linux, Instruments on macOS)
  - [ ] I/O profiling (iostat, iotop)
  - [ ] Memory profiling (valgrind, Instruments)
- [ ] Optimize based on profiling results
  - [ ] Platform-specific optimizations where beneficial
  - [ ] Ensure consistent performance across platforms

### 10.4 Memory Optimization
- [ ] Reduce memory allocations
  - [ ] Object pooling
  - [ ] Arena allocators
- [ ] Optimize data structure sizes
  - [ ] Packed structures
  - [ ] Remove padding
- [ ] Tune cache sizes dynamically

## Phase 11: Observability & Operations

### 11.1 Monitoring
- [ ] Add metrics collection
  - [ ] Write throughput (ops/sec, bytes/sec)
  - [ ] Read throughput
  - [ ] Latency percentiles (p50, p95, p99)
  - [ ] Cache hit rates
  - [ ] Compaction metrics
- [ ] Implement metrics export
  - [ ] Prometheus format
  - [ ] JSON API
- [ ] Add logging
  - [ ] Structured logging
  - [ ] Log levels (DEBUG, INFO, WARN, ERROR)
  - [ ] Rotation and retention

### 11.2 Configuration
- [ ] Implement configuration file parsing
  - [ ] TOML or INI format
  - [ ] Parameter validation
- [ ] Add runtime configuration
  - [ ] View current settings (SHOW command)
  - [ ] Modify settings (SET command)
- [ ] Document all configuration options

### 11.3 Backup & Restore
- [ ] Implement snapshot backup
  - [ ] Consistent point-in-time snapshot
  - [ ] Copy SSTables and WAL
- [ ] Implement incremental backup
  - [ ] Track changed SSTables
  - [ ] Backup only changes
- [ ] Implement restore
  - [ ] Copy files to data directory
  - [ ] Replay WAL if needed
- [ ] Add backup verification

### 11.4 Replication (Future)
- [ ] Design replication protocol
  - [ ] Streaming replication
  - [ ] Logical replication
- [ ] Implement primary-replica setup
- [ ] Add replica lag monitoring
- [ ] Implement failover (basic)

## Phase 12: Testing & Quality

### 12.1 Unit Tests
- [ ] Achieve 80%+ code coverage
- [ ] Test edge cases
  - [ ] Empty inputs
  - [ ] Large inputs
  - [ ] Concurrent access
- [ ] Test error paths

### 12.2 Integration Tests
- [ ] Test end-to-end workflows
  - [ ] Insert → Query
  - [ ] Update → Query
  - [ ] Delete → Query
- [ ] Test concurrent transactions
- [ ] Test recovery scenarios
- [ ] Test upgrade paths
- [ ] **Cross-Platform Integration Testing**
  - [ ] Run full test suite on Linux
  - [ ] Run full test suite on macOS
  - [ ] Verify consistent behavior across platforms
  - [ ] Test platform-specific I/O code paths
  - [ ] Test direct I/O (O_DIRECT vs F_NOCACHE)
  - [ ] Test fsync semantics (Linux vs macOS F_FULLFSYNC)

### 12.3 Postgres Compatibility Tests
- [ ] Run subset of Postgres regression tests
- [ ] Identify compatibility gaps
- [ ] Document unsupported features
- [ ] Prioritize compatibility fixes

### 12.4 Stress Testing
- [ ] Long-running stability tests
- [ ] High-throughput tests
- [ ] Large dataset tests (100GB+)
- [ ] Chaos testing (random failures)

## Phase 13: Documentation & Packaging

### 13.1 User Documentation
- [ ] Write installation guide
- [ ] Write configuration guide
- [ ] Write SQL reference (supported features)
- [ ] Add tutorials and examples
- [ ] Create troubleshooting guide

### 13.2 Developer Documentation
- [ ] Document architecture
- [ ] Document code organization
- [ ] Add inline code comments
- [ ] Create contribution guide
- [ ] Document testing procedures

### 13.3 Packaging
- [ ] Create installation packages
  - [ ] **Linux:** .deb (Debian/Ubuntu), .rpm (RedHat/CentOS)
  - [ ] **macOS:** .pkg installer, Homebrew formula
  - [ ] **Cross-platform:** Binary tarballs for both Linux and macOS
- [ ] Add Docker image (Linux-based)
- [ ] Publish to package repositories
  - [ ] apt repository (Linux)
  - [ ] Homebrew (macOS)
  - [ ] Docker Hub

### 13.4 Release Management
- [ ] Define versioning scheme (SemVer)
- [ ] Create release process
- [ ] Generate changelogs
- [ ] Tag releases in git
- [ ] Publish release notes

---

## Priority Order (Suggested)

**Critical Path (Must Have for MVP):**
1. Phase 1: Foundation (MemTable, SSTable, WAL)
2. Phase 2: LSM Engine (read/write paths, compaction)
3. Phase 4: Basic MVCC (XID, snapshots)
4. Phase 5: Query Engine (schema, catalog, basic executor)
5. Phase 7: Postgres Protocol (connection, query messages)
6. Phase 9.3: Crash Recovery (basic recovery)

**High Priority (For Beta):**
1. Phase 3: Buffer Pool & I/O (block cache, direct I/O)
2. Phase 6: Indexing (secondary indexes)
3. Phase 8: Query Planner (basic optimization)
4. Phase 10: Performance Tuning (SSD optimization)
5. Phase 11: Observability (metrics, logging)

**Medium Priority (Post-Launch):**
1. Phase 9: Advanced Features (transactions, savepoints)
2. Phase 10.2-10.4: Advanced Performance (parallelism, profiling)
3. Phase 11.3: Backup & Restore
4. Phase 12: Comprehensive Testing

**Low Priority (Future):**
1. Phase 11.4: Replication
2. Advanced SQL features (window functions, CTEs, etc.)
3. Advanced indexing (partial indexes, expression indexes)

---

## Estimated Effort

- **Total Tasks:** ~300 individual tasks
- **Estimated Timeline:** 6-9 months (1-2 developers full-time)
- **MVP (Critical Path):** 3-4 months
- **Beta (High Priority):** 5-6 months
- **Production Ready:** 9-12 months

## Notes

- Tasks are intentionally granular for tracking progress
- Each major task should have corresponding tests
- Benchmark after major phases to validate SSD optimizations
- Iterate on design based on performance results
- Focus on correctness before performance
- Document assumptions and trade-offs

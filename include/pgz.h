/*
 * pgz.h - C API header for the pgz storage engine
 *
 * This header defines the FFI interface for calling the Zig-based
 * storage engine from Go (or other languages via C).
 */

#ifndef PGZ_H
#define PGZ_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Error codes */
#define PGZ_OK        0   /* Success */
#define PGZ_ERR      -1   /* Generic error */
#define PGZ_NOT_FOUND 1   /* Key not found */

/* Opaque handles */
typedef struct DB DB;
typedef struct Transaction Transaction;
typedef struct Iterator Iterator;

/* ==========================================================================
 * Database Operations
 * ========================================================================== */

/*
 * Opens a database at the given path.
 * Returns a handle to the database, or NULL on error.
 */
DB* pgz_open(const char* path);

/*
 * Closes a database and frees its resources.
 */
void pgz_close(DB* db);

/* ==========================================================================
 * Transaction Operations
 * ========================================================================== */

/*
 * Begins a new transaction.
 * Returns a transaction handle, or NULL on error.
 */
Transaction* pgz_txn_begin(DB* db);

/*
 * Commits a transaction.
 * Returns PGZ_OK on success, PGZ_ERR on failure.
 */
int pgz_txn_commit(DB* db, Transaction* txn);

/*
 * Aborts a transaction.
 */
void pgz_txn_abort(DB* db, Transaction* txn);

/* ==========================================================================
 * Key-Value Operations
 * ========================================================================== */

/*
 * Gets a value by key within a transaction.
 *
 * On success (PGZ_OK), allocates memory for the value and sets out_val/out_len.
 * Caller must free the returned memory with pgz_free().
 *
 * Returns:
 *   PGZ_OK        - Value found
 *   PGZ_NOT_FOUND - Key does not exist
 *   PGZ_ERR       - Error occurred
 */
int pgz_get(DB* db, Transaction* txn,
            const char* key, size_t key_len,
            char** out_val, size_t* out_len);

/*
 * Puts a key-value pair within a transaction.
 * Returns PGZ_OK on success, PGZ_ERR on failure.
 */
int pgz_put(DB* db, Transaction* txn,
            const char* key, size_t key_len,
            const char* val, size_t val_len);

/*
 * Deletes a key within a transaction.
 * Returns PGZ_OK on success, PGZ_ERR on failure.
 */
int pgz_delete(DB* db, Transaction* txn,
               const char* key, size_t key_len);

/* ==========================================================================
 * Iterator Operations
 * ========================================================================== */

/*
 * Creates an iterator for scanning a key range [start_key, end_key).
 * Returns an iterator handle, or NULL on error.
 */
Iterator* pgz_scan(DB* db, Transaction* txn,
                   const char* start_key, size_t start_len,
                   const char* end_key, size_t end_len);

/*
 * Advances the iterator and returns the next key-value pair.
 *
 * On success (PGZ_OK), sets out_key/out_key_len and out_val/out_val_len.
 * Caller must free the returned memory with pgz_free().
 *
 * Returns:
 *   PGZ_OK        - Next pair returned
 *   PGZ_NOT_FOUND - Iterator exhausted
 *   PGZ_ERR       - Error occurred
 */
int pgz_iter_next(Iterator* iter,
                  char** out_key, size_t* out_key_len,
                  char** out_val, size_t* out_val_len);

/*
 * Closes an iterator and frees its resources.
 */
void pgz_iter_close(Iterator* iter);

/* ==========================================================================
 * Memory Management
 * ========================================================================== */

/*
 * Frees memory allocated by pgz_get or pgz_iter_next.
 */
void pgz_free(char* ptr, size_t len);

/* ==========================================================================
 * Utility
 * ========================================================================== */

/*
 * Returns the library version string.
 */
const char* pgz_version(void);

#ifdef __cplusplus
}
#endif

#endif /* PGZ_H */

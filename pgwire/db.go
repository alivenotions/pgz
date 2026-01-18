package pgwire

/*
#cgo CFLAGS: -I${SRCDIR}/../zig-out/include
#cgo LDFLAGS: -L${SRCDIR}/../zig-out/lib -lpgz

#include <stdlib.h>
#include <stdint.h>

// Opaque handles
typedef void* DBHandle;

// Error codes (must match Zig ErrorCode enum)
typedef enum {
    OK = 0,
    NOT_FOUND = 1,
    OUT_OF_MEMORY = 2,
    INVALID_ARG = 3,
    UNKNOWN = 99,
} ErrorCode;

// Function declarations (exported from Zig)
ErrorCode pgz_db_open(DBHandle* handle);
void pgz_db_close(DBHandle handle);
ErrorCode pgz_put(DBHandle handle, const uint8_t* key, size_t key_len,
                  const uint8_t* value, size_t value_len);
ErrorCode pgz_get(DBHandle handle, const uint8_t* key, size_t key_len,
                  uint8_t** value_out, size_t* value_len_out);
ErrorCode pgz_delete(DBHandle handle, const uint8_t* key, size_t key_len);
void pgz_free(uint8_t* ptr, size_t len);
*/
import "C"
import (
	"errors"
	"unsafe"
)

var (
	// ErrNotFound indicates the key was not found in the database
	ErrNotFound = errors.New("key not found")
	// ErrOutOfMemory indicates a memory allocation failure
	ErrOutOfMemory = errors.New("out of memory")
	// ErrInvalidArg indicates an invalid argument was provided
	ErrInvalidArg = errors.New("invalid argument")
	// ErrUnknown indicates an unknown error occurred
	ErrUnknown = errors.New("unknown error")
)

// DB represents a database instance backed by Zig
type DB struct {
	handle C.DBHandle
}

// Open creates a new database instance
func Open() (*DB, error) {
	var handle C.DBHandle
	errCode := C.pgz_db_open(&handle)

	if errCode != C.OK {
		return nil, mapError(errCode)
	}

	return &DB{handle: handle}, nil
}

// Close closes the database and frees all resources
func (db *DB) Close() {
	if db.handle != nil {
		C.pgz_db_close(db.handle)
		db.handle = nil
	}
}

// Put stores a key-value pair in the database
func (db *DB) Put(key, value []byte) error {
	if len(key) == 0 {
		return ErrInvalidArg
	}

	var keyPtr *C.uint8_t
	var valuePtr *C.uint8_t

	if len(key) > 0 {
		keyPtr = (*C.uint8_t)(unsafe.Pointer(&key[0]))
	}
	if len(value) > 0 {
		valuePtr = (*C.uint8_t)(unsafe.Pointer(&value[0]))
	}

	errCode := C.pgz_put(
		db.handle,
		keyPtr,
		C.size_t(len(key)),
		valuePtr,
		C.size_t(len(value)),
	)

	if errCode != C.OK {
		return mapError(errCode)
	}

	return nil
}

// Get retrieves a value by key from the database
func (db *DB) Get(key []byte) ([]byte, error) {
	if len(key) == 0 {
		return nil, ErrInvalidArg
	}

	var valuePtr *C.uint8_t
	var valueLen C.size_t

	errCode := C.pgz_get(
		db.handle,
		(*C.uint8_t)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
		&valuePtr,
		&valueLen,
	)

	if errCode != C.OK {
		return nil, mapError(errCode)
	}

	// Copy the data to Go-managed memory
	value := C.GoBytes(unsafe.Pointer(valuePtr), C.int(valueLen))

	// Free the Zig-allocated memory
	C.pgz_free(valuePtr, valueLen)

	return value, nil
}

// Delete removes a key-value pair from the database
func (db *DB) Delete(key []byte) error {
	if len(key) == 0 {
		return ErrInvalidArg
	}

	errCode := C.pgz_delete(
		db.handle,
		(*C.uint8_t)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
	)

	if errCode != C.OK {
		return mapError(errCode)
	}

	return nil
}

// mapError converts C error codes to Go errors
func mapError(code C.ErrorCode) error {
	switch code {
	case C.NOT_FOUND:
		return ErrNotFound
	case C.OUT_OF_MEMORY:
		return ErrOutOfMemory
	case C.INVALID_ARG:
		return ErrInvalidArg
	case C.UNKNOWN:
		return ErrUnknown
	default:
		return ErrUnknown
	}
}

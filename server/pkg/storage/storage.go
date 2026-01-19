// Package storage provides Go bindings for the pgz storage engine.
//
// This package uses cgo to call into the Zig-based storage engine
// via the C API defined in pgz.h.
package storage

/*
#cgo CFLAGS: -I${SRCDIR}/../../../zig-out/include
#cgo LDFLAGS: -L${SRCDIR}/../../../zig-out/lib -lpgz -Wl,-rpath,${SRCDIR}/../../../zig-out/lib

#include "pgz.h"
#include <stdlib.h>
*/
import "C"
import (
	"errors"
	"runtime"
	"unsafe"
)

var (
	ErrNotFound = errors.New("key not found")
	ErrDatabase = errors.New("database error")
)

// DB represents an open database.
type DB struct {
	ptr *C.DB
}

// Open opens a database at the given path.
func Open(path string) (*DB, error) {
	cpath := C.CString(path)
	defer C.free(unsafe.Pointer(cpath))

	ptr := C.pgz_open(cpath)
	if ptr == nil {
		return nil, errors.New("failed to open database")
	}

	db := &DB{ptr: ptr}
	runtime.SetFinalizer(db, (*DB).Close)
	return db, nil
}

// Close closes the database.
func (db *DB) Close() error {
	if db.ptr != nil {
		C.pgz_close(db.ptr)
		db.ptr = nil
	}
	return nil
}

// Txn represents a transaction.
type Txn struct {
	db  *DB
	ptr *C.Transaction
}

// Begin starts a new transaction.
func (db *DB) Begin() (*Txn, error) {
	ptr := C.pgz_txn_begin(db.ptr)
	if ptr == nil {
		return nil, errors.New("failed to begin transaction")
	}
	return &Txn{db: db, ptr: ptr}, nil
}

// Commit commits the transaction.
func (txn *Txn) Commit() error {
	if txn.ptr == nil {
		return errors.New("transaction already finished")
	}
	rc := C.pgz_txn_commit(txn.db.ptr, txn.ptr)
	txn.ptr = nil
	if rc != C.PGZ_OK {
		return ErrDatabase
	}
	return nil
}

// Abort aborts the transaction.
func (txn *Txn) Abort() {
	if txn.ptr != nil {
		C.pgz_txn_abort(txn.db.ptr, txn.ptr)
		txn.ptr = nil
	}
}

// Get retrieves a value by key.
func (txn *Txn) Get(key []byte) ([]byte, error) {
	if len(key) == 0 {
		return nil, errors.New("empty key")
	}

	var outVal *C.char
	var outLen C.size_t

	rc := C.pgz_get(
		txn.db.ptr,
		txn.ptr,
		(*C.char)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
		&outVal,
		&outLen,
	)

	switch rc {
	case C.PGZ_OK:
		result := C.GoBytes(unsafe.Pointer(outVal), C.int(outLen))
		C.pgz_free(outVal, outLen)
		return result, nil
	case C.PGZ_NOT_FOUND:
		return nil, ErrNotFound
	default:
		return nil, ErrDatabase
	}
}

// Put stores a key-value pair.
func (txn *Txn) Put(key, value []byte) error {
	if len(key) == 0 {
		return errors.New("empty key")
	}

	var valPtr *C.char
	var valLen C.size_t
	if len(value) > 0 {
		valPtr = (*C.char)(unsafe.Pointer(&value[0]))
		valLen = C.size_t(len(value))
	}

	rc := C.pgz_put(
		txn.db.ptr,
		txn.ptr,
		(*C.char)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
		valPtr,
		valLen,
	)

	if rc != C.PGZ_OK {
		return ErrDatabase
	}
	return nil
}

// Delete removes a key.
func (txn *Txn) Delete(key []byte) error {
	if len(key) == 0 {
		return errors.New("empty key")
	}

	rc := C.pgz_delete(
		txn.db.ptr,
		txn.ptr,
		(*C.char)(unsafe.Pointer(&key[0])),
		C.size_t(len(key)),
	)

	if rc != C.PGZ_OK {
		return ErrDatabase
	}
	return nil
}

// Iterator represents a range scan iterator.
type Iterator struct {
	ptr *C.Iterator
}

// Scan creates an iterator for the key range [start, end).
func (txn *Txn) Scan(start, end []byte) (*Iterator, error) {
	var startPtr, endPtr *C.char
	var startLen, endLen C.size_t

	if len(start) > 0 {
		startPtr = (*C.char)(unsafe.Pointer(&start[0]))
		startLen = C.size_t(len(start))
	}
	if len(end) > 0 {
		endPtr = (*C.char)(unsafe.Pointer(&end[0]))
		endLen = C.size_t(len(end))
	}

	ptr := C.pgz_scan(txn.db.ptr, txn.ptr, startPtr, startLen, endPtr, endLen)
	if ptr == nil {
		return nil, errors.New("failed to create iterator")
	}
	return &Iterator{ptr: ptr}, nil
}

// Next advances the iterator and returns the next key-value pair.
// Returns nil, nil, ErrNotFound when exhausted.
func (it *Iterator) Next() (key, value []byte, err error) {
	var outKey, outVal *C.char
	var outKeyLen, outValLen C.size_t

	rc := C.pgz_iter_next(it.ptr, &outKey, &outKeyLen, &outVal, &outValLen)

	switch rc {
	case C.PGZ_OK:
		key = C.GoBytes(unsafe.Pointer(outKey), C.int(outKeyLen))
		value = C.GoBytes(unsafe.Pointer(outVal), C.int(outValLen))
		C.pgz_free(outKey, outKeyLen)
		C.pgz_free(outVal, outValLen)
		return key, value, nil
	case C.PGZ_NOT_FOUND:
		return nil, nil, ErrNotFound
	default:
		return nil, nil, ErrDatabase
	}
}

// Close closes the iterator.
func (it *Iterator) Close() {
	if it.ptr != nil {
		C.pgz_iter_close(it.ptr)
		it.ptr = nil
	}
}

// Version returns the pgz library version.
func Version() string {
	return C.GoString(C.pgz_version())
}

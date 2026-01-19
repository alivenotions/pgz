// pgz-server is the PostgreSQL-compatible server.
//
// It handles the PG wire protocol, SQL parsing, and query planning,
// delegating storage operations to the Zig-based storage engine via FFI.
package main

import (
	"fmt"
	"log"
	"os"

	"github.com/alivenotions/pgz/go/pkg/storage"
)

func main() {
	fmt.Printf("pgz-server using libpgz version: %s\n", storage.Version())

	if len(os.Args) < 2 {
		log.Fatal("usage: pgz-server <db-path>")
	}

	dbPath := os.Args[1]

	// Open the database
	db, err := storage.Open(dbPath)
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}
	defer db.Close()

	fmt.Printf("Opened database at: %s\n", dbPath)

	// TODO: Start PostgreSQL wire protocol server
	// TODO: Initialize SQL parser
	// TODO: Initialize query planner

	fmt.Println("Server ready (not yet implemented)")
	fmt.Println("FFI connection verified!")
}

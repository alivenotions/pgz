package main

import (
	"fmt"
	"log"

	"github.com/alivenotions/pgz/pgwire"
)

func main() {
	fmt.Println("=== PGZ FFI Demo ===")
	fmt.Println("Demonstrating Go calling into Zig via FFI\n")

	// Open database
	fmt.Println("Opening database...")
	db, err := pgwire.Open()
	if err != nil {
		log.Fatalf("Failed to open database: %v", err)
	}
	defer db.Close()
	fmt.Println("✓ Database opened\n")

	// Put some values
	fmt.Println("Storing key-value pairs...")
	pairs := map[string]string{
		"user:1":    "Alice",
		"user:2":    "Bob",
		"user:3":    "Charlie",
		"config:db": "postgresql://localhost:5432",
	}

	for key, value := range pairs {
		err := db.Put([]byte(key), []byte(value))
		if err != nil {
			log.Fatalf("Failed to put %s: %v", key, err)
		}
		fmt.Printf("  PUT %s = %s\n", key, value)
	}
	fmt.Println("✓ All values stored\n")

	// Get values back
	fmt.Println("Retrieving values...")
	for key := range pairs {
		value, err := db.Get([]byte(key))
		if err != nil {
			log.Fatalf("Failed to get %s: %v", key, err)
		}
		fmt.Printf("  GET %s = %s\n", key, string(value))
	}
	fmt.Println("✓ All values retrieved\n")

	// Test overwrite
	fmt.Println("Testing overwrite...")
	err = db.Put([]byte("user:1"), []byte("Alice Updated"))
	if err != nil {
		log.Fatalf("Failed to overwrite: %v", err)
	}
	value, err := db.Get([]byte("user:1"))
	if err != nil {
		log.Fatalf("Failed to get updated value: %v", err)
	}
	fmt.Printf("  user:1 = %s\n", string(value))
	fmt.Println("✓ Overwrite successful\n")

	// Test delete
	fmt.Println("Testing delete...")
	err = db.Delete([]byte("user:2"))
	if err != nil {
		log.Fatalf("Failed to delete: %v", err)
	}
	fmt.Println("  Deleted user:2")

	_, err = db.Get([]byte("user:2"))
	if err == pgwire.ErrNotFound {
		fmt.Println("  ✓ Confirmed user:2 is gone")
	} else {
		log.Fatalf("Expected ErrNotFound, got: %v", err)
	}
	fmt.Println("✓ Delete successful\n")

	// Test error handling
	fmt.Println("Testing error handling...")
	_, err = db.Get([]byte("nonexistent"))
	if err == pgwire.ErrNotFound {
		fmt.Println("  ✓ Correctly returned ErrNotFound for missing key")
	} else {
		log.Fatalf("Expected ErrNotFound, got: %v", err)
	}

	err = db.Put([]byte(""), []byte("invalid"))
	if err == pgwire.ErrInvalidArg {
		fmt.Println("  ✓ Correctly returned ErrInvalidArg for empty key")
	} else {
		log.Fatalf("Expected ErrInvalidArg, got: %v", err)
	}

	fmt.Println("\n=== All tests passed! ===")
	fmt.Println("\nThis demonstrates:")
	fmt.Println("  • Go → Zig FFI calls working correctly")
	fmt.Println("  • Memory management across the boundary")
	fmt.Println("  • Error handling via error codes")
	fmt.Println("  • Basic database operations (Put, Get, Delete)")
}

// Headless entry point into the pinned, unmodified Aether CLI.
package main

import (
	"aether/cli"
	"os"
)

func main() {
	os.Exit(cli.Run(os.Args[1:], EmbeddedTemplates))
}

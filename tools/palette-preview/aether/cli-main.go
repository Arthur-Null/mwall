// Headless launcher for unmodified Aether CLI commands and embedded templates.
// Compile in the pinned upstream checkout alongside its templates.go.
package main

import (
	"aether/cli"
	"os"
)

func main() {
	os.Exit(cli.Run(os.Args[1:], EmbeddedTemplates))
}

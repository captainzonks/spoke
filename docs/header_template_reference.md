# Spoke Header Templates Reference Guide

<!-- 
==============================================================================
header_templates_reference.md - Comprehensive header template documentation
==============================================================================
Description: Complete reference guide for all Spoke file header templates
Author: Matt Barham
Created: 2025-07-30
Modified: 2026-01-20
Version: 2.1.0
==============================================================================
Document Type: Reference
Audience: Developer
Status: Final
==============================================================================
-->

## Overview

This document provides a comprehensive reference for all header templates available in the Spoke file creation system. The enhanced `new_file.sh` script generates standardized headers for various file types, ensuring consistency across all Spoke server infrastructure files.

## Table of Contents

- [Quick Start](#quick-start)
- [Script Languages](#script-languages)
- [Programming Languages](#programming-languages)
- [Web Technologies](#web-technologies)
- [Infrastructure Files](#infrastructure-files)
- [Documentation Files](#documentation-files)
- [Configuration Examples](#configuration-examples)
- [Best Practices](#best-practices)
- [Security Considerations](#security-considerations)

## Quick Start

### Basic Usage

```bash
# Basic syntax
new_file <type> <filepath> <description> [version]

# Examples
new_file rust src/config.rs "Application configuration management" 1.2.0
new_file python scripts/backup.py "Database backup automation" 2.1.0
new_file compose docker-compose.yml "Production stack deployment" 3.0.0
```

### Installation

```bash
# Make the script executable
chmod +x ~/.config/zsh/functions.d/new_file.sh

# Source it in your .zshrc (if not already sourced)
source ~/.config/zsh/functions.d/new_file.sh
```

## Script Languages

### Bash/Shell Scripts (`bash`, `shell`, `sh`)

**Usage**: `new_file bash script_name.sh "Script description"`

**Features**:
- Shebang: `#!/usr/bin/env bash`
- Security: `set -euo pipefail` and secure IFS
- Requirements section for dependencies
- Security notes section
- Documentation links section

**Example Output**:
```bash
#!/usr/bin/env bash
# ==============================================================================
# BACKUP_SCRIPT.SH
# ==============================================================================
# Description: Automated backup for Docker volumes
# Author: Matt Barham
# Created: 2025-07-30
# Modified: 2025-07-30
# Version: 1.0.0
# Host: Your Server
# ==============================================================================
# Requirements:
#   - Bash 4.0+
# Security Notes:
#   - Set -euo pipefail for safe execution
#   - Proper input validation
# Documentation:
#   - 
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Secure Internal Field Separator
```

### Python Scripts (`python`, `py`)

**Usage**: `new_file python script_name.py "Script description"`

**Features**:
- Shebang: `#!/usr/bin/env python3`
- Docstring with module description
- Logging configuration
- Security and dependency notes

**Example Output**:
```python
#!/usr/bin/env python3
# ==============================================================================
# DATABASE_MIGRATION.PY
# ==============================================================================
# Description: Database schema migration utility
# Author: Matt Barham
# Created: 2025-07-30
# Modified: 2025-07-30
# Version: 1.0.0
# Host: Your Server
# ==============================================================================
# Dependencies:
#   - Python 3.8+
# Security Notes:
#   - Input validation required
#   - Use secure coding practices
# Documentation:
#   - 
# ==============================================================================

"""
Database schema migration utility

This module provides...
"""

import logging
import sys
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)
```

### ZSH Scripts (`zsh`)

**Usage**: `new_file zsh function_name.zsh "Function description"`

**Features**: Same as Bash scripts but optimized for ZSH usage

## Programming Languages

### Rust (`rust`, `rs`)

**Usage**: `new_file rust src/module.rs "Module description"`

**Features**:
- Comprehensive header with dependencies and architecture notes
- Rust doc comments (`//!`) for module documentation
- Security and related files sections

**Example Output**:
```rust
// ==============================================================================
// CONFIG.RS - Application configuration management
// ==============================================================================
// Description: Application configuration management
// Author: Matt Barham
// Created: 2025-07-30
// Modified: 2025-07-30
// Version: 1.2.0
// Host: Your Server
// ==============================================================================
// Dependencies: [List main crates used]
// Security: [Security considerations]
// Architecture: [Brief architecture description]
// ==============================================================================
// Related Files:
//   - [List related files]
// Documentation:
//   - [Link to relevant documentation]
// ==============================================================================

//! Application configuration management
//!
//! [More detailed module documentation here]
```

### JavaScript (`javascript`, `js`)

**Usage**: `new_file javascript src/utils.js "Utility functions"`

**Features**:
- JSDoc-style header comments
- Node.js version requirements
- Security notes for ESLint rules
- Strict mode enabled

### TypeScript (`typescript`, `ts`)

**Usage**: `new_file typescript src/types.ts "Type definitions"`

**Features**:
- TypeScript-specific header with version requirements
- Type safety emphasis
- Modern Node.js compatibility

### Go (`go`)

**Usage**: `new_file go main.go "Main application entry point"`

**Features**:
- Go package declaration
- Standard imports (fmt, log)
- Go version requirements
- Security analysis tool recommendations

## Web Technologies

### HTML (`html`)

**Usage**: `new_file html index.html "Application landing page"`

**Features**:
- HTML5 doctype and semantic structure
- Meta tags for viewport, charset, and author
- Security considerations (CSP, HTTPS)
- Accessibility-focused structure

### CSS/SCSS/Sass (`css`, `scss`, `sass`)

**Usage**: `new_file css styles.css "Main application stylesheet"`

**Features**:
- Mobile-first responsive design notes
- CSS Grid and Flexbox architecture
- Browser support specifications
- CSS reset section starter

## Infrastructure Files

### Dockerfile (`dockerfile`, `docker`)

**Usage**: `new_file dockerfile Dockerfile "Production container image"`

**Features**:
- Multi-stage build ready
- Security hardening notes (non-root user)
- Build and run commands
- Architecture specifications

**Example Output**:
```dockerfile
# ==============================================================================
# DOCKERFILE - Production container image
# ==============================================================================
# Description: Production container image
# Author: Matt Barham
# Created: 2025-07-30
# Modified: 2025-07-30
# Version: 1.0.0
# Host: Your Server
# ==============================================================================
# Base Image: [Specify base image]
# Target Architecture: amd64
# Security: non-root user (UID:1000), minimal attack surface
# ==============================================================================
# Build Command:
#   docker build -t <image_name>:1.0.0 .
# Run Command:
#   docker run -d --name <container_name> <image_name>:1.0.0
# ==============================================================================
```

### Docker Compose (`compose`)

**Usage**: `new_file compose docker-compose.yml "Production stack"`

**Features**:
- Stack categorization (core, network, database, etc.)
- Environment generation instructions
- Security checklist (non-root, secrets, capabilities)
- External integrations checklist (Traefik, Authentik)

### YAML Configuration (`yaml`, `yml`)

**Usage**: `new_file yaml config.yml "Application configuration"`

**Features**:
- Security level classification
- Secret handling notes
- Schema validation references
- Dependency documentation

## Documentation Files

### Markdown (`markdown`, `md`)

**Usage**: `new_file markdown README.md "Project documentation"`

**Features**:
- HTML comment header (preserves in rendered markdown)
- Document metadata (type, audience, status)
- Automatic table of contents structure
- Getting started template

**Example Output**:
```markdown
# Project documentation

<!-- 
==============================================================================
README.md - Project documentation
==============================================================================
Description: Project documentation
Author: Matt Barham
Created: 2025-07-30
Modified: 2025-07-30
Version: 1.0.0
==============================================================================
Document Type: [Technical|User|API|Reference|Tutorial]
Audience: [Developer|Admin|End User]
Status: [Draft|Review|Final|Archived]
==============================================================================
-->

## Overview

Project documentation

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Documentation](#documentation)

## Getting Started

TODO: Add getting started instructions

## Documentation

- **Created**: 2025-07-30
- **Author**: Matt Barham
- **Version**: 1.0.0
```

### SQL Scripts (`sql`)

**Usage**: `new_file sql migration.sql "Database schema migration"`

**Features**:
- Database type specification
- Transaction safety (BEGIN, timeouts)
- Security permission notes
- Version requirements

### Plain Text (`txt`)

**Usage**: `new_file txt notes.txt "Project notes"`

**Features**: Generic header suitable for any text-based file

## Configuration Examples

### Environment Files (`env`)

**Usage**: `new_file env .env.production "Production environment variables"`

**Features**:
- Security level warning (HIGH for secrets)
- Secret handling documentation
- Related files cross-references

### JSON Configuration (`json`)

**Usage**: `new_file json config.json "Application configuration"`

**Features**:
- Metadata object with file information
- Schema validation references
- Structured approach to JSON documentation

### TOML Configuration (`toml`)

**Usage**: `new_file toml Cargo.toml "Rust project configuration"`

**Features**:
- TOML-native metadata section
- Security classification
- Validation tool references

## Best Practices

### File Naming Conventions

Use underscores for multi-word filenames (following user preferences):
```bash
# Good
new_file rust src/config_manager.rs "Configuration management module"
new_file bash scripts/backup_database.sh "Database backup automation"

# Avoid
new_file rust src/config-manager.rs "Configuration management module"
```

### Version Management

- Use semantic versioning (e.g., `1.2.0`)
- Update the "Modified" date when making changes
- Increment version numbers for significant changes

### Description Guidelines

- Use descriptive, action-oriented descriptions
- Start with a verb when appropriate
- Keep descriptions concise but informative
- Avoid redundant words like "script" or "file"

```bash
# Good descriptions
"Database backup automation"
"User authentication middleware"
"Production deployment configuration"

# Poor descriptions
"A script that backs up the database"
"Authentication file"
"Config"
```

## Security Considerations

### Script Security

All script templates include:
- `set -euo pipefail` for Bash scripts
- Input validation reminders
- Security analysis tool recommendations
- Proper error handling structures

### Configuration Security

Configuration file templates include:
- Security level classifications (HIGH/MEDIUM/LOW)
- Secret handling warnings
- Permission requirement notes
- Validation tool references

### Container Security

Docker templates emphasize:
- Non-root user execution (UID:1000/GID:968)
- Minimal attack surface
- Security scanning recommendations
- Capability dropping

## Advanced Usage

### Batch File Creation

```bash
# Create multiple related files
for file in config.rs database.rs auth.rs; do
    new_file rust "src/$file" "$(echo $file | sed 's/.rs$//' | tr '_' ' ') module" 1.0.0
done
```

### Custom Version Tracking

```bash
# Use date-based versioning
new_file python scripts/cleanup.py "System cleanup utility" "2025.07.30"

# Use build numbers
new_file compose docker-compose.yml "Production stack" "3.0.0-build.42"
```

### Integration with Git

```bash
# Create file and immediately commit
new_file rust src/new_feature.rs "New feature implementation" 1.0.0
git add src/new_feature.rs
git commit -m "Add new feature implementation module"
```

## Troubleshooting

### Common Issues

1. **File already exists**: The script will prompt for overwrite confirmation
2. **Directory doesn't exist**: Script automatically creates parent directories
3. **Permission denied**: Ensure script has execute permissions (`chmod +x new_file.sh`)
4. **Unknown file type**: Check the supported types list in the usage output

### Getting Help

```bash
# Show usage and supported types
new_file

# Show version
new_file --version

# Get help
new_file --help
```

---

**Documentation Version**: 2.1.0
**Last Updated**: January 20, 2026
**Author**: Matt Barham
**Host**: Your Server

## Related Files

- `.config/zsh/functions.d/new_file.sh` - Main script implementation
- `.config/zsh/features/50-functions.zsh` - ZSH function loader
- `scripts/README.md` - Scripts directory documentation

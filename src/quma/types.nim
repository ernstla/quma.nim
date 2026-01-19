## Core type definitions shared across quma modules.
##
## This module contains fundamental types that are used by multiple modules
## to avoid circular dependencies.

type ScriptId* = string ## Identifier for a script, typically a path like "users/getById"

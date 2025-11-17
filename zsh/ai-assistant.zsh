#!/usr/bin/env zsh
# AI Shell Assistant - ZSH Integration
# Provides Warp Terminal-like AI assistance using local LLM models

# Configuration
AI_SHELL_SOCKET="${AI_SHELL_SOCKET:-/tmp/ai-shell.sock}"
AI_SHELL_SUGGESTION_COLOR="${AI_SHELL_SUGGESTION_COLOR:-8}"  # Gray color for suggestions
AI_SHELL_ENABLE_INLINE="${AI_SHELL_ENABLE_INLINE:-1}"         # Enable inline suggestions
AI_SHELL_DEBUG="${AI_SHELL_DEBUG:-0}"                         # Debug mode

# Internal state
typeset -g _ai_shell_suggestion=""
typeset -g _ai_shell_suggestion_pending=0

# ============================================================================
# Socket Communication Functions
# ============================================================================

# Send JSON request to daemon via Unix socket
# Args: $1 = JSON payload
# Returns: JSON response via stdout
_ai_shell_send_request() {
    local payload="$1"
    local socket="$AI_SHELL_SOCKET"

    if [[ ! -S "$socket" ]]; then
        [[ $AI_SHELL_DEBUG -eq 1 ]] && echo "Error: Socket not found at $socket" >&2
        return 1
    fi

    # Find the Python client helper
    local client_script=""
    local script_dir="${0:A:h}"  # Directory of this script

    # Try to find ai-shell-client.py in common locations
    if [[ -f "${script_dir}/ai-shell-client.py" ]]; then
        client_script="${script_dir}/ai-shell-client.py"
    elif [[ -f "${HOME}/.zsh/ai-shell/ai-shell-client.py" ]]; then
        client_script="${HOME}/.zsh/ai-shell/ai-shell-client.py"
    elif [[ -f "${HOME}/.oh-my-zsh/custom/plugins/ai-shell/ai-shell-client.py" ]]; then
        client_script="${HOME}/.oh-my-zsh/custom/plugins/ai-shell/ai-shell-client.py"
    fi

    if [[ -z "$client_script" ]]; then
        [[ $AI_SHELL_DEBUG -eq 1 ]] && echo "Error: ai-shell-client.py not found" >&2
        return 1
    fi

    # Send request using Python client
    local response
    response=$(python3 "$client_script" "$socket" "$payload" 2>/dev/null)

    if [[ $? -eq 0 && -n "$response" ]]; then
        echo "$response"
        return 0
    fi

    [[ $AI_SHELL_DEBUG -eq 1 ]] && echo "Error: Failed to communicate with daemon" >&2
    return 1
}

# Create a request payload
# Args: $1 = type, $2 = command/task, $3 = additional context (optional)
_ai_shell_create_request() {
    local type="$1"
    local content="$2"
    local extra_context="$3"

    local id="req-$(date +%s)-$$"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local pwd_safe="${PWD/#$HOME/\~}"

    # Get recent command history
    local history_json="[]"
    if [[ -n "$HISTFILE" ]]; then
        local recent_cmds=$(fc -ln -10 | sed 's/^[[:space:]]*//' | jq -R -s -c 'split("\n") | map(select(length > 0))')
        [[ -n "$recent_cmds" ]] && history_json="$recent_cmds"
    fi

    # Get git branch if in a git repo
    local git_branch=""
    if git rev-parse --git-dir >/dev/null 2>&1; then
        git_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    fi

    # Build context object
    local context_obj=$(cat <<-EOF
		{
		  "history": $history_json,
		  "gitBranch": $(echo -n "$git_branch" | jq -R -s '.'),
		  "environment": {
		    "SHELL": "$SHELL",
		    "USER": "$USER",
		    "PWD": "$pwd_safe"
		  }
		}
	EOF
    )

    # Build payload based on request type
    local payload_obj
    case "$type" in
        suggest)
            payload_obj=$(cat <<-EOF
				{
				  "command": $(echo -n "$content" | jq -R -s '.'),
				  "workingDirectory": "$pwd_safe",
				  "context": $context_obj
				}
			EOF
            )
            ;;
        explain)
            payload_obj=$(cat <<-EOF
				{
				  "command": $(echo -n "$content" | jq -R -s '.'),
				  "workingDirectory": "$pwd_safe",
				  "context": $context_obj
				}
			EOF
            )
            ;;
        task)
            payload_obj=$(cat <<-EOF
				{
				  "task": $(echo -n "$content" | jq -R -s '.'),
				  "workingDirectory": "$pwd_safe",
				  "context": $context_obj
				}
			EOF
            )
            ;;
        health)
            payload_obj='{}'
            ;;
        *)
            echo "Error: Unknown request type: $type" >&2
            return 1
            ;;
    esac

    # Build complete request
    cat <<-EOF
		{
		  "id": "$id",
		  "type": "$type",
		  "payload": $payload_obj,
		  "timestamp": "$timestamp"
		}
	EOF
}

# ============================================================================
# AI Assistance Functions
# ============================================================================

# Get AI suggestion for current command
ai_shell_suggest() {
    local command="${1:-$BUFFER}"
    [[ -z "$command" ]] && return 1

    local request=$(_ai_shell_create_request "suggest" "$command")
    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')
        if [[ "$response_status" == "success" ]]; then
            echo "$response" | jq -r '.payload.suggestion // ""'
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            [[ $AI_SHELL_DEBUG -eq 1 ]] && echo "Error: $error_msg" >&2
        fi
    fi

    return 1
}

# Get AI explanation for command
ai_shell_explain() {
    local command="${1:-$BUFFER}"
    [[ -z "$command" ]] && return 1

    echo -n "Explaining command: $command ... "

    local request=$(_ai_shell_create_request "explain" "$command")
    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')
        echo ""  # Newline after "..."

        if [[ "$response_status" == "success" ]]; then
            local explanation=$(echo "$response" | jq -r '.payload.explanation // ""')
            local processing_time=$(echo "$response" | jq -r '.processingTime // 0')

            echo "$explanation"
            echo ""
            echo "$(tput dim)[Processing time: ${processing_time}s]$(tput sgr0)"
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            echo "Error: $error_msg"
        fi
    else
        echo "Failed to communicate with AI daemon"
    fi

    return 1
}

# Convert natural language task to shell commands
ai_shell_task() {
    local task="$@"
    [[ -z "$task" ]] && {
        echo "Usage: ai_shell_task <description of task>"
        echo "Example: ai_shell_task find all python files modified in last week"
        return 1
    }

    echo "Converting task to commands: $task"
    echo ""

    local request=$(_ai_shell_create_request "task" "$task")
    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')

        if [[ "$response_status" == "success" ]]; then
            local commands=$(echo "$response" | jq -r '.payload.commands // [] | .[]')

            if [[ -n "$commands" ]]; then
                echo "Suggested commands:"
                echo "---"
                echo "$commands"
                echo "---"
                echo ""
                echo -n "Execute these commands? [y/N] "
                read -r confirm

                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo ""
                    echo "$commands" | while IFS= read -r cmd; do
                        echo "$ $cmd"
                        eval "$cmd"
                        echo ""
                    done
                else
                    echo "Commands not executed. You can copy them manually."
                fi
            else
                echo "No commands generated."
            fi
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            echo "Error: $error_msg"
        fi
    else
        echo "Failed to communicate with AI daemon"
    fi

    return 1
}

# Check daemon health
ai_shell_health() {
    local request=$(_ai_shell_create_request "health" "")
    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')

        if [[ "$response_status" == "success" ]]; then
            echo "✓ AI Shell Assistant daemon is healthy"
            echo "  Socket: $AI_SHELL_SOCKET"
            return 0
        else
            echo "✗ AI Shell Assistant daemon reported an error"
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            echo "  Error: $error_msg"
        fi
    else
        echo "✗ Cannot communicate with AI Shell Assistant daemon"
        echo "  Socket: $AI_SHELL_SOCKET"
        echo "  Make sure the daemon is running: ai-shell-daemon"
    fi

    return 1
}

# ============================================================================
# ZLE (ZSH Line Editor) Integration
# ============================================================================

# Accept the current AI suggestion
_ai_shell_accept_suggestion() {
    if [[ -n "$_ai_shell_suggestion" ]]; then
        BUFFER="$_ai_shell_suggestion"
        _ai_shell_suggestion=""
        zle end-of-line
    fi
}

# Clear the current suggestion
_ai_shell_clear_suggestion() {
    _ai_shell_suggestion=""
    zle reset-prompt
}

# Show inline suggestion (like Fish shell)
_ai_shell_inline_suggest() {
    # Don't suggest if buffer is empty or too short
    [[ ${#BUFFER} -lt 3 ]] && return

    # Don't suggest if already pending
    [[ $_ai_shell_suggestion_pending -eq 1 ]] && return

    # Trigger async suggestion
    (
        _ai_shell_suggestion_pending=1
        local suggestion=$(ai_shell_suggest "$BUFFER")

        if [[ -n "$suggestion" && "$suggestion" != "$BUFFER" ]]; then
            _ai_shell_suggestion="$suggestion"
            # Signal to update display (use SIGUSR1)
            kill -USR1 $$ 2>/dev/null
        fi
        _ai_shell_suggestion_pending=0
    ) &!
}

# ZLE widget to accept suggestion with Tab
_ai_shell_zle_accept_suggestion() {
    if [[ -n "$_ai_shell_suggestion" ]]; then
        BUFFER="$_ai_shell_suggestion"
        _ai_shell_suggestion=""
        zle end-of-line
    else
        # Default tab behavior
        zle expand-or-complete
    fi
}

# ZLE widget to show explanation
_ai_shell_zle_explain() {
    if [[ -n "$BUFFER" ]]; then
        # Save current buffer
        local saved_buffer="$BUFFER"

        # Clear line and show explanation
        zle clear-screen
        ai_shell_explain "$saved_buffer"

        # Restore buffer
        BUFFER="$saved_buffer"
        zle reset-prompt
    fi
}

# ZLE widget to get suggestion manually
_ai_shell_zle_suggest() {
    if [[ -n "$BUFFER" ]]; then
        local suggestion=$(ai_shell_suggest "$BUFFER")

        if [[ -n "$suggestion" && "$suggestion" != "$BUFFER" ]]; then
            BUFFER="$suggestion"
            zle end-of-line
        fi
    fi
}

# Register ZLE widgets
zle -N _ai_shell_zle_accept_suggestion
zle -N _ai_shell_zle_explain
zle -N _ai_shell_zle_suggest

# ============================================================================
# Keybindings
# ============================================================================

# Ctrl+Space: Get AI suggestion
bindkey '^ ' _ai_shell_zle_suggest

# Ctrl+E (after moving to end): Explain command
bindkey '^Xe' _ai_shell_zle_explain

# Right arrow: Accept suggestion if available
# (Note: This is experimental and may interfere with normal navigation)
# bindkey '^[[C' _ai_shell_zle_accept_suggestion

# ============================================================================
# Initialization
# ============================================================================

# Check dependencies
_ai_shell_check_dependencies() {
    local missing=()

    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Warning: AI Shell Assistant requires the following dependencies:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        echo "" >&2
        if [[ " ${missing[@]} " =~ " python3 " ]]; then
            echo "Python 3 should be installed by default on macOS" >&2
        fi
        if [[ " ${missing[@]} " =~ " jq " ]]; then
            echo "Install jq with:" >&2
            echo "  brew install jq" >&2
        fi
        return 1
    fi

    return 0
}

# Auto-start daemon if not running
_ai_shell_auto_start() {
    if [[ ! -S "$AI_SHELL_SOCKET" ]]; then
        if command -v ai-shell-daemon >/dev/null 2>&1; then
            echo "Starting AI Shell Assistant daemon..."
            ai-shell-daemon &!
            sleep 1
        fi
    fi
}

# Initialize plugin
_ai_shell_init() {
    # Check dependencies
    _ai_shell_check_dependencies || return 1

    # Auto-start daemon if enabled
    if [[ "${AI_SHELL_AUTO_START:-0}" -eq 1 ]]; then
        _ai_shell_auto_start
    fi

    # Show welcome message
    if [[ -S "$AI_SHELL_SOCKET" ]]; then
        echo "AI Shell Assistant loaded. Available commands:"
        echo ""
        echo "  Core:"
        echo "    ai_shell_task <description>  - Convert natural language to commands"
        echo "    ai_shell_explain [command]   - Explain a command"
        echo "    ai_shell_health              - Check daemon status"
        echo ""
        echo "  Memory & RAG (Phase 2):"
        echo "    ai_shell_remember <fact>     - Store in long-term memory"
        echo "    ai_shell_recall <query>      - Query memory"
        echo "    ai_shell_index <file>        - Index documentation"
        echo "    ai_shell_search <query>      - Search indexed docs"
        echo ""
        echo "Keybindings:"
        echo "  Ctrl+Space  - Get AI suggestion for current command"
        echo "  Ctrl+X e    - Explain current command"
        echo ""
        echo "Aliases: ait, aix, aih, air, airc, aii, ais"
    else
        echo "AI Shell Assistant loaded (daemon not running)"
        echo "Start daemon with: ai-shell-daemon"
    fi
}

# Run initialization
_ai_shell_init

# ============================================================================
# Phase 2: Memory and RAG Commands
# ============================================================================

# Store a fact in long-term memory
ai_shell_remember() {
    local fact="$@"
    [[ -z "$fact" ]] && {
        echo "Usage: ai_shell_remember <fact to remember>"
        echo "Example: ai_shell_remember I prefer verbose git commits"
        return 1
    }

    local request=$(_ai_shell_create_request "remember" "" "")

    # Add fact to payload
    local id="req-$(date +%s)-$$"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    request=$(cat <<-EOF
		{
		  "id": "$id",
		  "type": "remember",
		  "payload": {
		    "fact": $(echo -n "$fact" | jq -R -s '.'),
		    "importance": 0.7
		  },
		  "timestamp": "$timestamp"
		}
	EOF
    )

    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')

        if [[ "$response_status" == "success" ]]; then
            echo "✓ Remembered: $fact"
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            echo "Error: $error_msg"
        fi
    else
        echo "Failed to communicate with AI daemon"
    fi

    return 1
}

# Query memory for relevant information
ai_shell_recall() {
    local query="$@"
    [[ -z "$query" ]] && {
        echo "Usage: ai_shell_recall <query>"
        echo "Example: ai_shell_recall git preferences"
        return 1
    }

    local id="req-$(date +%s)-$$"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    local request=$(cat <<-EOF
		{
		  "id": "$id",
		  "type": "recall",
		  "payload": {
		    "query": $(echo -n "$query" | jq -R -s '.')
		  },
		  "timestamp": "$timestamp"
		}
	EOF
    )

    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')

        if [[ "$response_status" == "success" ]]; then
            echo "Memories matching '$query':"
            echo "---"
            echo "$response" | jq -r '.payload.commands // [] | .[]'
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            echo "Error: $error_msg"
        fi
    else
        echo "Failed to communicate with AI daemon"
    fi

    return 1
}

# Index a file or documentation
ai_shell_index() {
    local file_path="$1"
    [[ -z "$file_path" ]] && {
        echo "Usage: ai_shell_index <file_path>"
        echo "Example: ai_shell_index README.md"
        echo "         ai_shell_index docs/**/*.md  # Index all markdown files"
        return 1
    }

    # Expand glob if needed
    local files=("${(@f)$(echo $file_path)}")

    if [[ ! -f "$file_path" ]]; then
        # Try glob expansion
        files=(${~file_path})
    else
        files=("$file_path")
    fi

    local indexed=0
    local failed=0

    for file in "${files[@]}"; do
        [[ ! -f "$file" ]] && continue

        echo -n "Indexing $file ... "

        local content=$(cat "$file" 2>/dev/null)
        [[ -z "$content" ]] && {
            echo "failed (empty or unreadable)"
            ((failed++))
            continue
        }

        local id="req-$(date +%s)-$$-$indexed"
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")
        local pwd_safe="${PWD/#$HOME/\~}"

        local request=$(cat <<-EOF
			{
			  "id": "$id",
			  "type": "index",
			  "payload": {
			    "filePath": $(echo -n "$file" | jq -R -s '.'),
			    "content": $(echo -n "$content" | jq -R -s '.'),
			    "workingDirectory": "$pwd_safe",
			    "importance": 0.8
			  },
			  "timestamp": "$timestamp"
			}
		EOF
        )

        local response=$(_ai_shell_send_request "$request")

        if [[ $? -eq 0 && -n "$response" ]]; then
            local response_status=$(echo "$response" | jq -r '.status // "error"')

            if [[ "$response_status" == "success" ]]; then
                echo "✓"
                ((indexed++))
            else
                echo "failed"
                ((failed++))
            fi
        else
            echo "failed"
            ((failed++))
        fi
    done

    echo ""
    echo "Indexed: $indexed files"
    [[ $failed -gt 0 ]] && echo "Failed: $failed files"

    return 0
}

# Search indexed documents
ai_shell_search() {
    local query="$@"
    [[ -z "$query" ]] && {
        echo "Usage: ai_shell_search <query>"
        echo "Example: ai_shell_search docker deployment"
        return 1
    }

    echo "Searching for: $query"
    echo ""

    local id="req-$(date +%s)-$$"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    local pwd_safe="${PWD/#$HOME/\~}"

    local request=$(cat <<-EOF
		{
		  "id": "$id",
		  "type": "search",
		  "payload": {
		    "query": $(echo -n "$query" | jq -R -s '.'),
		    "workingDirectory": "$pwd_safe"
		  },
		  "timestamp": "$timestamp"
		}
	EOF
    )

    local response=$(_ai_shell_send_request "$request")

    if [[ $? -eq 0 && -n "$response" ]]; then
        local response_status=$(echo "$response" | jq -r '.status // "error"')

        if [[ "$response_status" == "success" ]]; then
            echo "Results:"
            echo "---"
            echo "$response" | jq -r '.payload.commands // [] | .[]'
            return 0
        else
            local error_msg=$(echo "$response" | jq -r '.payload.error.message // "Unknown error"')
            echo "Error: $error_msg"
        fi
    else
        echo "Failed to communicate with AI daemon"
    fi

    return 1
}

# ============================================================================
# Aliases (optional convenience functions)
# ============================================================================

alias ait='ai_shell_task'
alias aix='ai_shell_explain'
alias aih='ai_shell_health'

# Phase 2 aliases
alias air='ai_shell_remember'
alias airc='ai_shell_recall'
alias aii='ai_shell_index'
alias ais='ai_shell_search'

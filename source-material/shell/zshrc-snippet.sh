# Excerpt from ~/.zshrc — the `gwg` / `gww` / `gww-clean` shell integration
# referenced in the "Shell Layer" slide. These wrap the util-scripts in this
# directory so a single command both creates a worktree and launches Claude
# Code with the right slash command pre-loaded.
#
# Place these functions/aliases in your own shell init file. Adjust the path
# (`~/src/util-scripts`) to wherever you put git-worktree-go /
# git-worktree-warp / git-worktree-warp-cleanup.

# Make the util-scripts available on PATH
export PATH="$PATH:$HOME/src/util-scripts"

# `gww-clean` — safe worktree teardown (refuses if uncommitted/unpushed)
alias gww-clean='git-worktree-warp-cleanup'

# `gww` — create a worktree and launch Claude Code with no pre-loaded prompt
gww() {
  local worktree_path
  worktree_path=$("$HOME/src/util-scripts/git-worktree-warp" "$@") \
    && cd "$worktree_path" \
    && claude --dangerously-skip-permissions
}

# `gwg` — parse branch prefix (feat/fix/chore) → route to /feature, /bugfix,
# or /chore with the ticket ID pre-loaded. This is the one-command shipping
# entry point from the talk.
gwg() {
  local output worktree_path claude_prompt
  output=$("$HOME/src/util-scripts/git-worktree-go" "$@") || return 1
  worktree_path=$(echo "$output" | head -1)
  claude_prompt=$(echo "$output" | tail -1)
  cd "$worktree_path" && claude --dangerously-skip-permissions "$claude_prompt"
}

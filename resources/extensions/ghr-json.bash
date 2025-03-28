#!/bin/bash

# get the current directory and generate the JSON file path
current_dir="$(pwd)"
json_file_path="$current_dir/repos.json"

# Get the list of all managed repositories (excluding debug messages and `.git` internal paths)
mapfile -t repo_paths < <(ghr list --path --verbose)

# Initialize JSON output with empty array
echo "[]" >"$json_file_path"

# Process each repository path
for path in "${repo_paths[@]}"; do
    # Remove Windows extended-length path prefix
    clean_path="${path#"\\\\?\\"}"

    # Extract repo name (last directory in the path)
    repo_name=$(basename "$clean_path")

    printf '🗃️ Repository: "%s"\n' "$repo_name"

    # Check if it's a Git repository
    if [[ ! -d "$clean_path/.git" ]]; then
        echo "⚠️ Skipped non-repository: $clean_path"
    else
        if ! cd "$clean_path"; then
            echo "⚠️ Failed to check path: $clean_path"
            continue
        fi

        # Check if working directory is clean
        pristine="false"
        if [[ -z $(git status --porcelain) ]]; then
            pristine="true"
        fi

        # Check if all commits are pushed
        pushed="false"
        if git branch -v | grep -q "ahead"; then
            pushed="false"
        else
            pushed="true"
        fi

        # Safe to delete if pristine and pushed
        safe_to_delete="false"
        if [[ "$pristine" == "true" && "$pushed" == "true" ]]; then
            safe_to_delete="true"
        fi

        git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "🚫 Not a repo"; exit 1; }
        branch=$(git rev-parse --abbrev-ref HEAD)
        status=$(git status --porcelain)
        [ -z "$status" ] && dirty="✅ Clean" || dirty="⚠️ $(echo "$status" | wc -l) changes"

        if git status | grep -q "Untracked files"; then
            state="🆕 Untracked files"
        elif git status | grep -q "Changes not staged"; then
            state="✏️ Modified"
        elif git status | grep -q "Changes to be committed"; then
            state="📌 Staged changes"
        elif git status | grep -q "Your branch is ahead"; then
            state="⬆️ Commits to push"
        else
            state="🔄 Synced"
        fi

        # Update JSON content
        content=$(<"$json_file_path")
        content="${content%]}"

        # Add comma if not first entry
        if [ "$content" != "[" ]; then
            content="$content,"
        fi

        # Append new entry and write back
        printf '%s\n{"name":"%s","path":"%s","pristine":%s,"pushed":%s,"safe_to_delete":%s}]' \
            "$content" \
            "$repo_name" \
            "${clean_path//\\/\\\\}" \
            "$pristine" \
            "$pushed" \
            "$safe_to_delete" >"$json_file_path"

        printf "> 🌿 %s | %s | %s\n" "$branch" "$dirty" "$state"
        printf "> '%s'\n" "$clean_path"
        if [ ! "$safe_to_delete" = "true" ]; then
            printf "> 🚫 !! Do not delete !!\n"
        fi
    fi
done

# JSON is already properly formatted by jq
echo "]" >>"$json_file_path"

if command -v cygpath &> /dev/null; then
    win_path=$(cygpath -w "$json_file_path")
    echo "JSON file '$win_path' generated."
else
    echo "JSON file '$json_file_path' generated."
fi

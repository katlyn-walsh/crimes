#!/usr/bin/env bash
# affine-backup.sh
#
# Copies the AFFiNE desktop workspace data into a local Git repository,
# then stages, commits (always — even if nothing changed), and pushes to
# GitHub.  Designed to be run by launchd so ALL paths are absolute and
# no shell expansion of ~ is relied upon.
#
# Source:  /Users/katlyn.walsh/Library/Application Support/AFFiNE/workspaces/
# Dest:    /Users/katlyn.walsh/affine-backup/workspaces/
# Remote:  git@github.com:katlyn.walsh/affine-backup.git  (branch: main)

set -euo pipefail

AFFINE_DATA_DIR="/Users/katlyn.walsh/Library/Application Support/AFFiNE/workspaces"
BACKUP_REPO_DIR="/Users/katlyn.walsh/affine-backup"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting AFFiNE backup"

# Sync workspace data into the repo, mirroring deletions
rsync -a --delete \
    "${AFFINE_DATA_DIR}/" \
    "${BACKUP_REPO_DIR}/workspaces/"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] rsync complete, committing"

cd "${BACKUP_REPO_DIR}"

git add -A
git commit --allow-empty -m "Affine backup $(date '+%Y-%m-%d %H:%M:%S')"
git push origin main

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup complete"

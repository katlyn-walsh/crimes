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
# 
# Uses rsync -a --delete to sync workspace data into the backup repo, 
# then git add -A, git commit --allow-empty (always commits, even on quiet days), and git push origin main.
# All paths are absolute so it runs correctly without a shell environment.
#
# Changes are pushed over SSH with the existing github key.
#
# launchd agent — ~/Library/LaunchAgents/com.affine.backup.plist
# Registered as a macOS user agent. Runs the script every day at 2:00 AM, survives reboots,
# and logs to ~/logs/affine-backup.log.
# 
# To restore: quit Affine, copy the workspaces/ folder from the repo back to 
# ~/Library/Application Support/AFFiNE/workspaces/, reopen Affine.

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

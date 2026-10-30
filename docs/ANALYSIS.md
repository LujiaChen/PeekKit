# Folder analysis

The summary is always compact; click **Analysis** for File types, Largest files, or Scope & omissions. Click a large-file result to preview it, or use its context menu to reveal/copy its path.

## Scope and accounting

- Current folder and descendants; changing folders starts a new scan.
- Application/package contents are traversed. The browser itself still treats packages as files.
- Hidden entries follow Show hidden files. Name filtering affects browsing, not analysis.
- Only readable regular files are measured. Size is `st_size`; On disk is `st_blocks × 512`. Directory metadata is excluded.
- Hard links are deduplicated by device/inode. APFS clones/shared blocks are not deduplicated; On disk is not exclusive space or a deletion savings estimate.
- Symlinks are skipped, including loops and outside links. Other devices/volumes and special files are skipped.
- SF_DATALESS and un-downloaded iCloud entries are omitted. Unknown residency metadata is conservatively omitted. The analyzer does not open file contents or request downloads/network access. Real third-party cloud-provider behavior has not been integration-tested.
- Extensions are lowercased filename suffixes, not content-based format detection. Files without extensions have their own bucket.

## Progress and bounded work

A utility worker streams the directory tree, publishing snapshots about every 250 ms. Progress shows visited entries rather than an invented percentage. A separate observable model avoids re-sorting the browser list on every update.

Limits: **1,000,000 entries, 128 levels, 60 seconds**, 256 extension buckets plus Other extensions, 20 largest files per metric, and the first 16 issue paths. Hard-link identity storage is bounded by the entry cap. The browser independently displays at most 20,000 immediate entries.

Stop, preview dismissal, replacement requests, folder navigation and hidden-scope changes cancel the old task. Generation IDs reject stale results. In-flight filesystem/provider calls cannot be forcibly interrupted; cancellation completes when the call returns.

## Partial results

Unreadable/changed entries, cloud omissions, other volumes, active scans, stopping and limits are shown as partial results. Hidden files and symlinks are deliberate scope exclusions and are separately counted. Omitted subtree descendant counts and bytes are unknown.

This is a live scan, not an atomic filesystem snapshot. Concurrent modifications can affect results. Folder size may differ from Finder, `du`, storage settings or a cloud provider because of different scope/allocation rules.

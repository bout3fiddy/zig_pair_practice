# Zig Pair Practice

This repository is a scaffold for slow, agent-guided Zig practice.

It is meant to be used with a coding agent that reads `AGENTS.md`, checks the
local progress files, and guides the learner through small lessons over time.
The agent asks one focused question, reviews the answer, assigns a small coding
task when useful, and records only enough progress to make the next session
targeted.

To resume a session, tell the agent: `start the study session`. The agent should
read the local instructions and progress, then continue from the current lesson
without requiring a new plan.

## Scope

The public repository contains the reusable coaching scaffold and study notes.
Learner progress, active scratch work, and copyrighted source material stay
local.

## How The Study Loop Works

The agent should use the current lesson pack and local progress files to choose
one concrete next step. A normal session is small:

- ask a short code-reading question tied to the current lesson;
- review the learner's answer directly;
- assign a focused Zig task only when the target is clear;
- review the code for correctness, data shape, boundaries, ownership,
  allocation, loop shape, and evidence;
- update local progress only after a meaningful checkpoint.

Updates to this repository should make that loop clearer, more precise, and
easier to reuse.

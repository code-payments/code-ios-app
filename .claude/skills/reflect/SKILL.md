---
name: reflect
description: Write a reflection about a situation that got out of hand during this session
disable-model-invocation: true
argument-hint: "[short-topic-name]"
---

# Write a Reflection

Create a reflection entry documenting a situation from this session where things went off track.

## Steps

1. Create a new file at `.claude/reflections/YYYY-MM-DD-$ARGUMENTS.md` using today's date and the topic name provided.

2. Use this structure for the reflection:

```
# <Descriptive Title>

**Date:** YYYY-MM-DD

## The Bug / Task

What was the original problem or request?

## Root Cause

What was actually causing the issue?

## What Went Wrong

### Attempt N: <short label>
Describe each failed or problematic attempt. What was tried, why it seemed reasonable, and what broke.

Repeat for each attempt.

## Lessons

Numbered list of actionable takeaways. Focus on what to do differently next time, not just what went wrong.
```

3. Update `.claude/reflections/index.md` by adding a new line to the list with a link to the new file and a one-sentence summary.

4. If `.claude/reflections/index.md` does not exist, create it with the header `# Reflections` and a description, then add the entry.

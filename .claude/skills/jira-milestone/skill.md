# Jira Milestone Skill

Manages Jira epics for FFU Builder GSD milestones.

## Commands

| Command | Description |
|---------|-------------|
| `/jira-milestone create <version>` | Create epic for milestone |
| `/jira-milestone start <version>` | Transition epic to In Progress |
| `/jira-milestone update <version>` | Update epic with current progress |
| `/jira-milestone complete <version>` | Transition epic to Done |
| `/jira-milestone status` | Show all mapped milestones |

## Usage

```bash
/jira-milestone create v1.9.0    # Create epic for milestone
/jira-milestone start v1.9.0     # Move epic to In Progress
/jira-milestone update v1.9.0    # Update epic progress
/jira-milestone complete v1.9.0  # Close epic when done
/jira-milestone status           # List all mappings
```

## Workflow

### Create Epic (`create`)

1. Read `.planning/ROADMAP.md` for milestone details
2. Extract phase list and requirements count
3. Create Jira epic using `mcp__plugin_atlassian_atlassian__createJiraIssue`
4. Store epic key in `.planning/jira/mapping.json`
5. Display created epic link

**Required Fields for RTS Project Epics:**

The RTS project requires these fields when creating epics:

| Field | Parameter | Format | Notes |
|-------|-----------|--------|-------|
| Summary | `summary` | string | Epic title |
| Description | `description` | markdown | Epic description |
| Due Date | `duedate` | "YYYY-MM-DD" | Required system field |
| Epic Start Date | `customfield_10553` | "YYYY-MM-DD" | Required custom field |
| Account | `customfield_10224` | integer | **Must be numeric ID, not object** |
| Labels | `labels` | array | Optional: `["ffu-builder", "milestone"]` |

**Account Field Values:**

| ID | Value | Use For |
|----|-------|---------|
| 4 | New Development | New features and milestones |
| 5 | Maintenance | Bug fixes and maintenance |
| 6 | Small Demands | Small tasks |

**Example `additional_fields` parameter:**

```json
{
  "duedate": "2026-01-31",
  "customfield_10553": "2026-01-25",
  "customfield_10224": 4,
  "labels": ["ffu-builder", "milestone"]
}
```

**IMPORTANT:** The `customfield_10224` (Account) must be a plain integer (e.g., `4`), NOT an object like `{"id": 4}`. Using an object format will cause a deserialization error.

### Start Epic (`start`)

1. Read `.planning/jira/mapping.json` to get epic key for version
2. Verify epic exists using `mcp__plugin_atlassian_atlassian__getJiraIssue`
3. Transition to In Progress using `mcp__plugin_atlassian_atlassian__transitionJiraIssue`
4. Update mapping.json with status "In Progress"
5. Display confirmation with epic link

**Required Parameters:**

```json
{
  "cloudId": "a04fcb6a-ae5a-4f81-95e7-83941226b47b",
  "issueIdOrKey": "RTS-107",
  "transition": { "id": "31" }
}
```

**Example:**

```
/jira-milestone start v1.9.2
```

Transitions RTS-107 to "In Progress" status.

---

**Epic Description Template:**

```markdown
## Milestone: {version} {name}

### Goal
{milestone goal from ROADMAP.md}

### Scope
- Phases: {phase_range} ({phase_count} phases)
- Requirements: {requirement_count} total

### Progress
{checklist of phases with status}

### Links
- Repository: https://github.com/joanderson/FFUBuilder
- Branch: feature/improvements-and-fixes
- Planning: .planning/ROADMAP.md
```

### Update Progress (`update`)

1. Read `.planning/ROADMAP.md` for current phase status
2. Calculate progress (X/Y phases complete)
3. Add comment to epic using `mcp__plugin_atlassian_atlassian__addCommentToJiraIssue`
4. Display update confirmation

**Comment Format:**

```markdown
## Progress Update - {date}

**Status**: {X}/{Y} phases complete ({percentage}%)

### Completed Phases
- Phase N: {name} - Completed {date}

### In Progress
- Phase N: {name}

### Remaining
- Phase N: {name}
```

### Complete Epic (`complete`)

1. Read `.planning/milestones/{version}-MILESTONE-AUDIT.md` if exists
2. Add final comment with audit summary
3. Transition epic to Done using `mcp__plugin_atlassian_atlassian__transitionJiraIssue`
4. Update mapping.json with status "completed"
5. Display completion confirmation

**Required Parameters for Transition:**

```json
{
  "cloudId": "a04fcb6a-ae5a-4f81-95e7-83941226b47b",
  "issueIdOrKey": "RTS-107",
  "transition": { "id": "41" }
}
```

**RTS Project Transition IDs:**

| ID | Name | Target Status | Use For |
|----|------|---------------|---------|
| **41** | **Done** | Done (green) | **Completing milestones** |
| 7 | Canceled | Canceled (green) | Abandoned milestones |
| 31 | In Progress | In Progress (yellow) | Active work |
| 2 | To Do | To Do (blue) | Not started |
| 11 | Backlog | Backlog (blue) | Deferred work |
| 5 | In Testing | In Testing (yellow) | QA phase |
| 6 | UAT | UAT (yellow) | User acceptance |
| 8 | Ready to Deploy | Ready to Deploy (blue) | Awaiting deployment |

**Example transition call:**

```
mcp__plugin_atlassian_atlassian__transitionJiraIssue(
  cloudId: "a04fcb6a-ae5a-4f81-95e7-83941226b47b",
  issueIdOrKey: "RTS-107",
  transition: { id: "41" }
)
```

### Status (`status`)

1. Read `.planning/jira/mapping.json`
2. Display table of all milestones with their epic keys and status

## Configuration

**Mapping File:** `.planning/jira/mapping.json`

```json
{
  "cloudId": "a04fcb6a-ae5a-4f81-95e7-83941226b47b",
  "projectKey": "RTS",
  "epicIssueTypeId": "10000",
  "requiredFields": {
    "duedate": "YYYY-MM-DD format",
    "customfield_10553": "Epic start date (YYYY-MM-DD)",
    "customfield_10224": "Account ID (integer: 4=New Dev, 5=Maintenance, 6=Small)"
  },
  "transitions": {
    "done": { "id": "41", "name": "Done" },
    "canceled": { "id": "7", "name": "Canceled" },
    "inProgress": { "id": "31", "name": "In Progress" },
    "toDo": { "id": "2", "name": "To Do" },
    "backlog": { "id": "11", "name": "Backlog" }
  },
  "milestones": {
    "v1.9.0": {
      "epicKey": "RTS-XXX",
      "status": "in_progress",
      "created": "2026-01-23"
    }
  }
}
```

**RTS Project Custom Fields Reference:**

| Custom Field ID | Name | Type | Required |
|-----------------|------|------|----------|
| `customfield_10553` | Epic start date | date | Yes |
| `customfield_10224` | Account | integer | Yes |
| `customfield_10001` | Team | team | No |
| `customfield_10031` | Goals | array | No |

## MCP Tools Used

- `mcp__plugin_atlassian_atlassian__createJiraIssue` - Create epic
- `mcp__plugin_atlassian_atlassian__addCommentToJiraIssue` - Update progress
- `mcp__plugin_atlassian_atlassian__transitionJiraIssue` - Complete epic
- `mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue` - Get available transitions
- `mcp__plugin_atlassian_atlassian__getJiraIssue` - Verify epic exists

## Integration with GSD

| GSD Event | Jira Action |
|-----------|-------------|
| `/gsd:new-milestone` | Run `/jira-milestone create` |
| `/gsd:execute-phase` (first phase) | Run `/jira-milestone start` |
| `/gsd:execute-phase` completed | Run `/jira-milestone update` |
| `/gsd:complete-milestone` | Run `/jira-milestone complete` |

## Error Handling

- **Epic already exists**: Prompt to update instead
- **Epic not found**: Offer to create new one
- **Transition failed**: Show available transitions
- **Network error**: Retry with backoff

### Common Creation Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `"duedate": "Due date is required."` | Missing duedate field | Add `"duedate": "YYYY-MM-DD"` to additional_fields |
| `"customfield_10553": "Epic start date is required."` | Missing epic start date | Add `"customfield_10553": "YYYY-MM-DD"` to additional_fields |
| `"customfield_10224": "Account is required."` | Missing account field | Add `"customfield_10224": 4` to additional_fields |
| `"Can not deserialize instance of java.lang.Long out of START_OBJECT token"` | Account field passed as object | Use integer `4` not `{"id": 4}` |

### Common Transition Errors

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `"Transition id 'X' is not valid"` | Wrong transition ID | Use ID from transitions table (Done = "41") |
| `"Issue does not exist"` | Wrong issue key | Verify epic key in mapping.json |
| `"It is not on the appropriate status"` | Transition not available from current status | Check current status, may need intermediate transition |

### Troubleshooting Checklist

**For Creation:**
1. **Check required fields**: RTS project requires duedate, customfield_10553, and customfield_10224
2. **Verify field formats**: Dates as "YYYY-MM-DD", Account as plain integer
3. **Use `getJiraIssueTypeMetaWithFields`** to discover project-specific requirements if errors persist

**For Transitions:**
1. **Check transition ID**: Use `"41"` for Done, `"7"` for Canceled
2. **Verify epic exists**: Call `getJiraIssue` first to confirm
3. **Use `getTransitionsForJiraIssue`** to see available transitions from current status

# SRE Agent testing

[Project README](../Readme.md) | [Access setup](./Implementation-Guide.md#5-configure-sre-agent-access) | [Incident demo](./Incident-Demo.md)

**Updated:** November 16, 2026. Historical observations retain their original dates. Use the approved nonproduction VM and synthetic evidence only.

## Contents

- [Supply context once](#supply-context-once)
- [Ask a simple question](#ask-a-simple-question)
- [Approve and verify execution](#approve-and-verify-execution)
- [Configure reusable context](#configure-reusable-context)
- [Test realistic incident analysis](#test-realistic-incident-analysis)
- [Validation status](#validation-status)
- [Record each outcome](#record-each-outcome)

## Supply context once

Complete [agent access/readiness](./Implementation-Guide.md#58-verify-readiness-before-the-first-investigation), then generate the smoke-test bootstrap in PowerShell 7 from the package root with the verified `@target`:

```powershell
.\scripts\New-AgentPrompt.ps1 @target `
    -CorrelationId '33333333-3333-3333-3333-333333333333'
```

Paste the **entire generated output** into a new agent conversation in **Review** mode, not the PowerShell command. Generation produces text only; it supplies the VM, fixed reader, current hash and approved payload.

If the agent asks for the reader, supply that complete output. Do not copy a hash from an old screenshot or remove the hash check. VS Code conversations and local repository files are not automatically available to SRE Agent.

**Checkpoint:** Approved target and dataset-specific reader context are available. Missing context should cause a question, not a guessed target.

## Ask a simple question

After bootstrap, or when an approved skill has the required context:

**Negative control**

```text
Find SharePoint log entries for correlation ID
33333333-3333-3333-3333-333333333333 on the approved lab VM.
```

**Positive control**

```text
Find SharePoint log entries for correlation ID
11111111-1111-1111-1111-111111111111 on the approved lab VM.
```

For each GUID, require a **fresh payload for that GUID** and approval. A new conversation needs the approved context again unless configured through the skill.

**Wrong flow:** If the agent treats the GUID as `--subscription`, searches Azure resources for it, or offers OBO for that mistaken command, **Cancel**. Restore context; do not broaden permissions.

## Approve and verify execution

1. Review the exact subscription, **VM lab RG**, VM and correlation ID.
2. Check **Action Run Command / RunPowerShellScript**, fixed reader path and current hash.
3. Approve only that action. It executes as **SYSTEM**; instructions do not enforce read-only authority.
4. Inspect the actual tool trace, stdout/stderr and JSON, not only the final explanation.

| Check | Pass condition |
|---|---|
| Execution | Fresh successful agent tool call to the intended VM; no guest errors |
| Identity | Intended UAMI evidenced; record OBO separately. If not exposed, leave identity verification open |
| Source | Correct physical VM and `C:\SP-SRE-Lab\Synthetic-ULS.log` |
| Freshness | New `queryUtc`; fixed synthetic event timestamps are not retrieval time |
| Positive GUID `1111...` | Exactly **2** matches, `partial = false`, cited evidence/line numbers |
| Negative GUID `3333...` | **0** matches, `partial = false`, empty `evidence` |
| Explanation | Claims limited to retrieved evidence; no invented root cause or farm-health conclusion |

A failed command is not a zero-result success. Do not automatically retry a timeout; an administrator must first inspect command state. Manual output, answer keys or remembered results are not agent acceptance.

## Configure reusable context

Configure once to avoid long user questions. This is an **Azure SRE Agent portal skill**, not a VS Code agent customization.

1. Open **Builder > Agent Canvas > Create skill**, or the current **Skills** page.
2. Name it `sharepoint-log-investigation`.
3. Copy the description and instructions from the maintained [skill template](./templates/sharepoint-log-investigation.md). Paste the template before selecting tools so the picker can maintain tool metadata.
4. Expand **Azure Operation** using its arrow. Select individual tools, not the entire category:

   | Tool | Purpose |
   |---|---|
   | `RunAzCliWriteCommands` | Required for `az vm run-command invoke` |
   | `RunAzCliReadCommands` | Recommended for approved state inspection |
   | `GetAzCliHelp` | Optional syntax help |

5. Supply the approved VM, dataset, reader paths/hashes and payload through approved configuration/supporting context. The generated bootstrap is also available for conversation-specific context. Do not upload private setup files or the answer key.
6. Save, retain Review mode, and test the short negative question in a **new conversation**.

**Checkpoint:** Observe skill activation, correct payload, approval and a fresh zero-match result. Skill creation, activation, execution and UAMI verification are separate gates.

Run Command requires a Write tool because it is SYSTEM-capable, even for log reads. Tools/skills do not grant RBAC. No MCP, Kusto or SharePoint connector is needed.

References: [Create a skill](https://learn.microsoft.com/azure/sre-agent/create-skill) | [Attach tools](https://learn.microsoft.com/azure/sre-agent/skills#attach-tools) | [Agent permissions](https://learn.microsoft.com/azure/sre-agent/permissions).

## Test realistic incident analysis

Use the [incident walkthrough](./Incident-Demo.md#run-an-actual-sre-agent-investigation), not the smoke reader. It owns scenario IDs, per-page commands and coverage checks. Retrieve every required page before analysis; the final page alone does not establish completeness.

## Validation status

These are **dated historical lab observations**, not guarantees for a new deployment or validation of the renamed November 16 generic package. Private environment screenshots and repository/run links are omitted. Revalidate each environment and release:

| Area | Recorded status |
|---|---|
| Generic customer package, November 16 | Package checks and 178 workflow/transport/automation/Bastion/smoke/incident checks passed locally; all three Bicep templates compiled. Two Windows PowerShell 5.1 compatibility checks were blocked by workstation signing policy, then explicitly skipped for the remaining regression runs. ACL application and Azure calls were mocked; no new live deployment or agent acceptance is claimed |
| Incident VM installation/manual reads | Verified October 28: installed hashes, 638 records, restricted guest ACLs and ten reads across five cases |
| Agent provisioning/VM grant | Successful provisioning and grant evidence supplied October 29 |
| Optional Bastion desktop access, November 12 | Missing RDP exception created; saved and NIC-effective subnet NSG rules verified. VM Agent Ready and Bastion Developer Succeeded. Browser login remains unverified. This does not establish SRE Agent acceptance |
| SRE Agent test | **Operator reported working on October 29** after context guidance; case-by-case traces, execution identity and complete scenario coverage were not supplied for this record |
| Reusable skill | Creation/activation/short-question acceptance not separately evidenced |
| Automated deployment | Local mocked coverage exists; live end-to-end `azd up` remains unverified |
| Local/fresh-clone validation, October 29 | All six suites and all three Bicep builds passed in a fresh local Git clone; pinned readers and incident data retained identical hashes. Both local Windows PowerShell compatibility checks were explicitly skipped after signing-policy failures |
| Hosted Windows CI, October 29 | Recorded as passing all six suites and three Bicep builds, including both Windows PowerShell compatibility checks without skips. Private run link omitted. Hosted-runner success does not prove live Azure authorization, guest ACL enforcement or agent acceptance |

The operator's success is recorded without claiming independently reviewed traces or that all incident scenarios passed. Revalidate each environment and release.

## Record each outcome

Retain this information in an approved **private** evidence record:

| Field | Record |
|---|---|
| Case / time | Dataset, correlation ID, UTC and pass/fail/not-run |
| Target / identity | Exact VM and observed UAMI/OBO identity |
| Integrity | Approved reader/data hashes |
| Execution | Actual tool trace, stdout/stderr and approval |
| Coverage | Counts, `partial`, page set and unique line references |
| Analysis | Evidence citations, supported findings and unknowns |

Keep raw IDs/traces out of shared source. Capture errors, fixes and their actual verification in an approved private record. Do not mark skipped or unevidenced cases passed.

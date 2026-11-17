# SRE Agent testing

[Project README](../Readme.md) | [Access setup](./Implementation-Guide.md#5-configure-sre-agent-access) | [Incident demo](./Incident-Demo.md)

**Updated:** November 17, 2026. Historical observations retain their original dates. Use the approved nonproduction VM and synthetic evidence only.

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

Internal error numbers below refer to the separately retained troubleshooting record. That record and its screenshots are not included in this customer package; obtain an approved sanitized extract from the release owner if required. Earlier rows describe their recorded stage and can be superseded by later outcomes at the top.

| Area | Recorded status |
|---|---|
| Operator-reported successful agent retest, November 17 | After reporting the UAMI grant correction, the operator stated "It worked this time." Record successful SRE retest as operator-reported. No fresh tool response, caller claims, query UTC or separate positive/negative outputs accompanied that statement; do not infer which controls passed or independently verify UAMI execution. Retain the final acceptance evidence before customer sign-off. Internal error 34 records the recovery report |
| Operator-reported UAMI correction, November 17 | Operator reports correcting the wrong-identity grant; a prominent UAMI-selection NOTE is now in step 5.7 and internal error 34. Saved assignment details were not supplied for independent verification. Inspect the saved current-UAMI/role/VM scope and retain actual caller/new query UTC for both controls; do not treat OBO or prior portal output as UAMI acceptance |
| Reported wrong-principal grant and proposed repair, November 17 | A subsequent supplied agent investigation identifies the deleted grant as the UAMI's and the replacement grant as the system-assigned identity's, explaining the earlier mismatch if accurate. Raw assignment exports were not independently reviewed. The proposed correction was to assign the existing approved VM-only role to the confirmed current UAMI, not the agent-named system identity; review the unintended grant separately after validation. No repair result was supplied at this stage. New thread recommended for clean testing, not as proof that OBO state clears. File-delivery causality remains unverified. Internal error 34 |
| Reported caller switch and principal discrepancy, November 17 | Supplied agent Activity Log analysis reports managed-identity callers for agent runs through November 12, versus the operator through the Azure SRE Agent application on November 17. Raw events/approval records were not supplied for independent verification. The earlier saved member-selection screenshot's Object-ID prefix differs from the reported historical managed-identity caller. At this stage the current UAMI/grant required confirmation and no corrective grant was evidenced. Missing/wrong access was a hypothesis, not a proven cause of file-expansion failure. Internal error 34 |
| Manual implementation parity review, November 17 | Compared guide, core setup/grant/test/prompt scripts, shared CLI helper, azd hooks and supplied history. No additional missing guest installation script identified for the smoke-reader path. Portal replaces the wrappers; the prompt generator is text-only; the built-in-role JSON is reference data. Agent Review mode, managed lab RG, active tools/context, exact UAMI/saved grant, negative control and file ACL evidence remain verification gates, not proven skipped steps. No Azure operations performed. Internal error 32 |
| Assisted portal retrieval and agent analysis, November 17 | Operator supplied an SRE Agent answer summarizing the existing portal result at 17:23:42 UTC: four lines read, two matches, `partial = false`, evidence lines 2 and 3. It distinguished synthetic events from real SharePoint events and ordering from causation. This records a working manual-retrieval-plus-agent-analysis path, not a new successful agent VM invocation; no fresh execution trace was supplied at this stage. Claimed memory update is agent-reported only. Internal error 33 |
| Portal positive-control retest, November 17 | New screenshot shows the hash-checked script on separate lines and successful reader JSON at `2026-11-17T17:23:42.4618481Z`: correct synthetic source/file and positive GUID, four lines read, two matching records, `partial = false`, evidence lines 2 and 3, no visible guest error. This resolves the manual portal parser failure below and establishes positive portal-to-VM retrieval. It does not by itself establish agent identity/acceptance; separate portal negative-control output remains pending. Internal error 33 |
| Portal manual fallback parse failure, November 17 | Operator text and screenshot show guest `script30.ps1` with joined statements and `UnexpectedToken` at `$reader` and `if` on line 1. No reader result in that attempt. A separator-preserving manual payload passed a local parser-only check, not VM execution. Later portal success supersedes this failure's open status; this fallback does not validate agent execution. Internal error 33 |
| Agent guest parse failure, November 17 | A subsequent file-based attempt reported guest Run Command `script29.ps1` failing at line 1 on literal `@/root/...` with `UnrecognizedToken`. Screenshots show the reviewed current-path/hash payload and the file-reference invocation, not the final result; the guest error is separately supplied text. The intended reader did not run in that attempt. The earlier file proposal was therefore tested and failed; actual principal and successful agent retrieval were unverified at that stage. Do not broaden RBAC or remove the hash check to resolve payload parsing. Internal error 32 |
| Agent tool validation, November 17 | After stale-context guidance, the supplied candidate payload uses the current reader path/hash, but the reported Azure execution-tool result is `ValidationError`, empty output and `routedViaSandbox = true`. No reader evidence returned. The agent reports stopping before VM execution; symbol-rejection and workspace explanations remain hypotheses. A file-based CLI attempt was proposed at this stage, before the later guest parse failure. Assignment/identity and successful retrieval were unverified at this stage. Internal error 30 |
| Manual reader mismatch, November 17 | Earlier VM output failed on the obsolete source path. The later screenshot shows the installed reader hash matching the current working-package reference, successful evidence from the intended synthetic file, exactly two positive matches, `partial = false` and two line-referenced records without displayed errors. The local positive-test failure is resolved in supplied evidence; exact replacement steps were not supplied. This local result alone does not establish remote transport or agent acceptance. Internal error 27 |
| Manual-route progress, November 17 | Operator explicitly reports step 4.2 works using VM-local PowerShell, not Azure Portal. The positive result is screenshot-evidenced; completion of the negative control is operator-reported within that statement, with no separate negative-result output supplied. Expanded file ACL entries remain unevidenced. Operator reports both their agent and the customer agent already created and chooses portal VM role assignment next. Verify Review mode, intended UAMI, managed-resource scope and existing grants before adding access; follow [step 5.7 Option B](./Implementation-Guide.md#option-b-manually). Customer site access, remote transport, fresh agent execution, identity verification and real-log integration remain separate open gates |
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

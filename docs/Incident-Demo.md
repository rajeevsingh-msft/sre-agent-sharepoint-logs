# Synthetic incident demo

[Project README](../Readme.md) | [Implementation guide](./Implementation-Guide.md) | [Agent testing](./SRE-Agent-Testing.md)

Optional richer evidence for the same private VM. All events, messages, servers, URLs and incidents are **invented synthetic examples**. SharePoint is not installed; simulated server fields are not additional deployed VMs.

## Contents

- [Dataset and scenarios](#dataset-and-scenarios)
- [Install on your existing lab VM](#install-on-your-existing-lab-vm)
- [Inspect and test the evidence](#inspect-and-test-the-evidence)
- [Run an actual SRE Agent investigation](#run-an-actual-sre-agent-investigation)
- [Evaluation rubric - not execution evidence](#evaluation-rubric---not-execution-evidence)
  - [SQL connection timeout example](#sql-connection-timeout-example)
  - [Other scenarios and controls](#other-scenarios-and-controls)
- [Reader contract and safeguards](#reader-contract-and-safeguards)
- [Files and local validation](#files-and-local-validation)

## Dataset and scenarios

The [638-record TSV](../data/SharePoint-IncidentDemo-v1.tsv) contains 600 background records, 36 scenario records and two unrelated high-severity records. Every message starts with `SYNTHETIC DEMO:`.

Columns: `Timestamp`, `Server`, `Process`, `TID`, `Area`, `Category`, `EventID`, `Level`, `Message`, `Correlation`.

| Scenario | Correlation ID | Records | Pages, zero-based |
|---|---|---|---|
| SQL connection timeouts | `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1` | 12 | 0, 1, 2 |
| Claims certificate trust failure | `bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2` | 8 | 0, 1 |
| Search query unavailable | `cccccccc-cccc-4ccc-8ccc-ccccccccccc3` | 8 | 0, 1 |
| Successful request control | `dddddddd-dddd-4ddd-8ddd-ddddddddddd4` | 8 | 0, 1 |
| Absent correlation control | `eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5` | 0 | 0 |

Scenario timestamps are fixed on October 28, 2026; `queryUtc` records retrieval time. Demo event IDs are not actual SharePoint product-event definitions. Nearby unrelated errors must not be mixed into an investigation.

## Install on your existing lab VM

Use PowerShell 7 in the package root with the verified `@target` from [step 1](./Implementation-Guide.md#1-select-your-account-and-target). Skip installation if this exact package is already verified.

```powershell
.\scripts\Initialize-IncidentDemo.ps1 @target -WhatIf
.\scripts\Initialize-IncidentDemo.ps1 @target
```

Approve the SYSTEM write to the intended VM. Expect `kind = uls-incident-demo-initialized`, `synthetic = true` and matching reader/data hashes.

**Guest paths:**

```text
C:\SP-SRE-Lab\IncidentDemo-v1\
    SharePoint-IncidentDemo-v1.tsv
    Read-IncidentDemo.ps1
```

The smoke files remain unchanged. Identical files are retained; different existing files are refused. Keep v1 immutable and review a versioned upgrade rather than editing installed evidence.

## Inspect and test the evidence

For all five manual cases:

```powershell
.\scripts\Test-IncidentDemo.ps1 @target
```

Expected: **ten sequential reads**, returning **12 / 8 / 8 / 8 / 0** records across the cases. Allow several minutes; no performance SLA is implied.

To inspect one SQL page:

```powershell
$incident = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
$page = .\scripts\Get-IncidentDemoEvidence.ps1 @target -CorrelationId $incident -Page 0
$page | ConvertTo-Json -Depth 6
```

SQL returns four events per page. `hasMore` is true / true / false for pages 0 / 1 / 2. **Every SQL page has `partial = true`, including the last.** The final page does not prove earlier pages were retrieved.

Run one operation at a time. Stop on timeout and inspect command/extension state before retrying. Manual reads are not agent acceptance.

## Run an actual SRE Agent investigation

Complete [agent access](./Implementation-Guide.md#5-configure-sre-agent-access) and retain Review mode.

1. Generate SQL page 0 locally, then paste the **entire output** into a new agent conversation:

   ```powershell
   .\scripts\New-IncidentDemoPrompt.ps1 @target -Page 0
   ```

2. Review the exact VM, pinned reader/data hashes and payload. Approve only that action.
3. Check the actual successful tool trace, stdout/stderr, source, hash, fresh `queryUtc`, GUID and page contract.
4. After reviewing page 0, generate page 1 and repeat approval in the **same conversation**:

   ```powershell
   .\scripts\New-IncidentDemoPrompt.ps1 @target -Page 1
   ```

5. After reviewing page 1, repeat for page 2:

   ```powershell
   .\scripts\New-IncidentDemoPrompt.ps1 @target -Page 2
   ```

6. Confirm **12 unique line references** from the same source, dataset hash and GUID. Then ask:

   > Using only the retrieved evidence, reconstruct the timeline. Cite event IDs, servers and line numbers. Separate the observed failure mechanism from unproven causes. List missing evidence and suggested validation checks; do not execute remediation.

For other cases, pass their `-CorrelationId` to the same generator and approve each required page separately. The absent case uses page 0 only.

**Acceptance:** Fresh agent execution, correct counts, complete page set and evidence-based explanation. Do not supply the answer key in place of retrieval. Use the [private outcome record](./SRE-Agent-Testing.md#record-each-outcome).

## Evaluation rubric - not execution evidence

This is an **illustrative answer key**, not an actual SRE Agent result. Evaluate only after the agent retrieves the required evidence.

### SQL connection timeout example

- `ds001-ds003`: Request starts on simulated `SP-WFE-DEMO01`; authentication succeeds and a connection to `SQL-DEMO01` / `SP_Content_Demo` begins.
- `ds004-ds008`: First connection times out after 30 seconds; TCP provider error 10060 is reported. The application's retry also times out.
- `ds009-ds010`: Request returns HTTP 500 after **60,120 ms**.
- `ds011-ds012`: No successful query or verified recovery. This is one request, not measured farm-wide impact.
- **Supported mechanism:** Failure to establish the SQL connection, not a recorded slow query or rejected SharePoint login.
- **Not established:** Stopped SQL, DNS, firewall, routing or listener configuration as the underlying cause.
- **Suggested next evidence:** Authorized service/listener checks, hostname resolution, configured-port connectivity, routing/firewall review and correlated SQL/Windows events. Do not assume port 1433 or restart services.

### Other scenarios and controls

| Scenario | Supported finding | Unsupported claim |
|---|---|---|
| Claims | `da003-da006`: UntrustedRoot chain failure, failed token issuance, HTTP 401 | Wrong password, expired certificate or SQL outage |
| Search | `dq004-dq006`: query timeout, cached degraded topology, HTTP 503 | Corrupt index or farm-wide outage |
| Successful request | `dh001-dh008`: this request returned HTTP 200 | Entire farm healthy or earlier SQL incident repaired |
| Absent correlation | No matches in this file after a bounded complete scan | No incident occurred |

## Reader contract and safeguards

- Fixed versioned file, exact GUID matching, **four events per page**.
- Full messages up to **320 characters**; longer messages fail, not silently truncate.
- Source caps: **1 MiB / 5,000 records**. Exceeding either fails explicitly.
- Output cap: **2,800 UTF-8 bytes**, below the common helper's 3,000-byte budget and Run Command's 4,096-byte tail.
- Metadata: fresh UTC, physical VM source, dataset hash, total count, continuation, coverage and source line numbers.
- Reject invalid pages, missing/locked sources, reparse points, malformed data and hash mismatches.
- Installer stages bounded compressed data in a temporary UTF-8 script, avoiding `az.cmd` size limits; temporary transport files are cleaned up.
- SYSTEM/Administrators ACLs are intended. Review mode, hashes and instructions do not create an authorization sandbox.

## Files and local validation

| File | Purpose |
|---|---|
| [Dataset](../data/SharePoint-IncidentDemo-v1.tsv) / [generator](../scripts/New-IncidentDemoData.ps1) | Deterministic synthetic v1 data |
| [Workstation installer](../scripts/Initialize-IncidentDemo.ps1) | Confirmed installation and hash/readiness checks |
| [Guest initializer](../scripts/Initialize-IncidentDemoGuest.ps1) / [reader](../scripts/Read-IncidentDemo.ps1) | Fixed guest-only installation and bounded retrieval |
| [Evidence wrapper](../scripts/Get-IncidentDemoEvidence.ps1) / [prompt generator](../scripts/New-IncidentDemoPrompt.ps1) | Manual retrieval or reviewed agent payload |
| [Manual cloud acceptance](../scripts/Test-IncidentDemo.ps1) / [local tests](../tests/Test-IncidentDemo.ps1) | Separate live and mocked checks |

See [local validation commands](../Readme.md#validation) and the dated [validation status](./SRE-Agent-Testing.md#validation-status). Local tests mock Azure and ACL application; they do not establish live enforcement.

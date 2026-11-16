# Automated lab setup with azd up

[Back to the README](../Readme.md) | [Learning walkthrough](./Implementation-Guide.md)

Use one command to prepare the VM lab, then concentrate on configuring SRE Agent and investigating its logs. This is an **additional path**, not a replacement for the step-by-step learning process.

**Updated:** October 29, 2026. **Validation boundary:** Live end-to-end `azd up` remains unverified. Local tests do not establish cloud deployment or guest enforcement; see the shared [validation status](./SRE-Agent-Testing.md#validation-status).

## Contents

- [Before you start](#before-you-start)
- [Run one command](#run-one-command)
- [What happens automatically](#what-happens-automatically)
- [Continue at step 5](#continue-at-step-5)
- [Settings and private state](#settings-and-private-state)
- [Rerun or recover](#rerun-or-recover)
- [Clean up](#clean-up)
- [Files and local validation](#files-and-local-validation)

## Before you start

- Use a Windows workstation with **PowerShell 7**, Azure CLI, its Bicep component and **azd 1.11.1 or later**, installed through your approved process. Scripts do not install or upgrade tools or bypass signing policy.
- Have an approved nonproduction Azure public-cloud subscription, tenant, region, VM size and spending owner. This subscription-scoped adapter needs permission to create a dedicated resource group and subscription deployment as well as its Compute/Network resources. Access limited to an existing resource group is insufficient.
- Approve the costs and privileged SYSTEM Run Command used to install/test the synthetic files. An SRE Agent Administrator and RBAC owner are needed later, not for an automatic agent grant.
- **Approve azd's secret handling before starting.** The required secure VM-password parameter is prompted by azd and may be retained in its local secret cache. Do not assume that `@secure()` means nothing is stored locally, or that a local vault is necessarily organization-approved encrypted storage. If this caching is not permitted, use the [learning path](./Implementation-Guide.md) instead.
- Obtain the complete package. Keep local azd state and tool caches out of source, uploads, archives, screenshots and transcripts.

**While following the manual path:** Keep doing so in your current terminal. Do not run this automated path against that lab. Automated resource groups use a separate `rg-sp-sre-azd-<environment>` name; existing manual groups are not adopted.

## Run one command

Open PowerShell 7 in the **package root**, then run:

```powershell
azd up
```

For a new environment, choose a name such as **`poc1-auto`** when azd prompts. Names must be 2-10 lowercase letters, digits or hyphens, beginning with a letter and ending with a letter or digit.

Respond to the prompts for:

1. Azure Developer CLI authentication, subscription and region, as needed by azd. If azd stops and requests `azd auth login`, complete that one-time sign-in through your approved process and rerun `azd up`.
2. The secure VM administrator password. azd initializes required parameters before the custom progress messages begin. Never supply the password through `azd env set`, source parameters, command arguments or chat.
3. Your approved tenant and any missing VM settings. The hook verifies Azure CLI context separately; it requests **LOGIN** approval if that CLI needs sign-in.
4. **TARGET** confirmation of the displayed tenant, subscription, dedicated resource group, VM, region and VM size.
5. **REGISTER** approval for each missing required provider, if any. Already registered providers are left alone.
6. Azure CLI's secure password prompt for ARM what-if. Use the same approved password as the deployment parameter. Review the preview and costs, then type **PROVISION** to allow azd to deploy.
7. **INITIALIZE** approval for privileged guest setup after deployment and VM Agent readiness checks.

**One command is one entry point, not zero interaction.** The preview and native azd deployment use separate secure parameter handling, so password input can be requested more than once. Do not use `--no-prompt` or `--debug` for this interactive lab workflow.

No separate package/build/app-deploy stage is needed: the custom `up` workflow runs native `azd provision`, with pre/post-provision hooks doing the operational work.

## What happens automatically

The progress display uses six operational stages. These are progress counters, **not replacements for the seven implementation-guide steps**.

| Progress | Work performed | Matching Quickstart step |
|---|---|---|
| `[1/6]` | Check tools, load settings, verify account and target | 1. Select your account and target |
| `[2/6]` | Check/register approved missing providers; validate SKU, quota and image | 2. Check prerequisites |
| `[3/6]` | Check the dedicated group, run what-if, obtain approval; let azd provision once | 3. Preview and deploy the lab |
| `[4/6]` | Verify a successful deployment, poll VM Agent readiness, install fixture and exact reader | 4. Create logs and test the reader |
| `[5/6]` | Run both manual cases; require 2 and 0 matches, complete coverage and the expected guest source | 4. Create logs and test the reader |
| `[6/6]` | Print completion and the nonsecret target block for the agent exercise | Handoff to step 5 |

Illustrative completion message, **not a captured Azure result**:

```text
[6/6] Lab preparation complete. Manual VM-log retrieval passed.
SRE Agent integration is NOT yet verified. No agent access was granted.
Next: docs/Implementation-Guide.md, step 5 - Configure SRE Agent access.
```

The deployment uses the same [VM template](../infra/main.bicep), [initialization](../scripts/Initialize-Lab.ps1) and [manual tests](../scripts/Test-Lab.ps1) as the learning path. It does not install SharePoint, copy actual customer logs, create an agent, grant agent permissions or start agent investigations.

## Continue at step 5

1. Copy the printed `$target` block into the PowerShell terminal you will use for the agent exercise. It contains your private target identifiers; do not publish it.
2. Follow [step 5: Configure SRE Agent access](./Implementation-Guide.md#5-configure-sre-agent-access). Use Review mode and obtain the separate RBAC owner's approval. Run Command authorizes SYSTEM commands, not an enforced read-only file role.
3. Follow [step 6: Run the agent investigations](./Implementation-Guide.md#6-run-the-agent-investigations). Require fresh tool executions, the expected source/path, two positive matches, zero negative matches and `partial = false`. Manual test success is not agent success.
4. Follow [step 7: Verify completion and clean up](./Implementation-Guide.md#7-verify-completion-and-clean-up).

Do not rerun learning steps 1-4 on the automated lab just to follow both guides.

## Settings and private state

Nonsecret settings are saved per azd environment, so a new terminal does not lose them.

| Setting | Meaning |
|---|---|
| `AZURE_ENV_NAME` | Selected environment; derives the RG and VM names |
| `AZURE_SUBSCRIPTION_ID`, `POC1_TENANT_ID` | Approved account scope; verified by the hook |
| `AZURE_LOCATION` | Region selected by azd or supplied at setup |
| `POC1_VM_SIZE` | Explicit size, or `Standard_D2s_v5` when accepting the initial prompt default |
| `POC1_IMAGE_VERSION` | Published version resolved by preflight; an existing lab retains its deployed version |
| `POC1_PROVISION_APPROVED_UTC` | Approval time; guest setup requires a successful nested deployment at or after this time |
| `AZURE_RESOURCE_GROUP`, `POC1_VM_NAME`, `POC1_VM_ID` | Nonsecret deployment outputs; targets must match the environment-derived names |

There is **no silent region/SKU fallback**. To select a different approved combination, set nonsecret values in the package root before running `azd up`:

```powershell
azd env set AZURE_LOCATION eastus2
azd env set POC1_VM_SIZE Standard_D2s_v6
azd up
```

The above is an optional configuration example, not a capacity guarantee. That combination passed an operator preflight on October 28; the workflow rechecks availability/quota at execution time. The manual script defaults remain unchanged.

The package excludes its entire `.azure` directory from Git. Omit it from manual distribution too. Native azd may also keep local user-level secret material outside the package; manage that through your approved process. Never copy or inspect those caches for documentation, and do not assume resource cleanup deletes them.

## Rerun or recover

- **Before provisioning fails:** Read the exact error, correct the specific setting or permission, then rerun `azd up`. No broad role grants, unapproved provider registration or automatic region changes are used as workarounds.
- **An existing group is found:** Reuse requires the matching azd environment tags, original region/size, a successful `poc1-vm` deployment pointing to the expected VM, and no unexpected resources. Tags alone are not authorization or proof of ownership. Shared/manual groups are refused. The existing preflight conservatively budgets another VM's vCPUs even on reruns, so quota headroom is still required.
- **Provisioning partially completed:** Inspect the subscription deployment and every resource in the dedicated group. A missing/failed nested deployment is not automatically adopted. Recover with the platform owner or perform the separately reviewed cleanup; do not keep rerunning against uncertain state.
- **VM Agent is not ready:** Only status reads are polled, up to 30 attempts with 10-second delays. Read failures stop immediately. No guest command is submitted until readiness is established.
- **Guest initialization or a manual test failed/timed out:** An administrator must inspect Run Command/extension status first. There are no automatic guest retries. Once no command is running and the target/files are verified, recover just the post-provision phase from the package root:

  ```powershell
  .\scripts\azd\postprovision.ps1
  ```

  This still requires the recorded successful provisioning, target checks and explicit INITIALIZE approval. Identical fixtures are left unchanged; changed files fail rather than being overwritten.

- **A preview was run:** Preview alone must never trigger guest setup. The post-hook rejects a deployment older than the latest provisioning approval. Use `azd up` for this supported workflow rather than invoking additional native preview modes.
- **Changing region or size:** Use a new azd environment for a fresh lab. Existing-lab relocation/resizing is intentionally blocked and is not an implicit rerun operation.

Record actual failures and verified fixes in an approved private record. Keep raw evidence and account details private. Do not run manual and automated operations concurrently on the same VM.

## Clean up

Automatic `azd down` is **blocked** by a failing pre-down hook. This avoids treating group-wide deletion as a safe default or forgetting the separate agent role definition.

Use [step 7 cleanup](./Implementation-Guide.md#cleanup) with the automated lab's printed `$target`, not the manual lab target. Retain approved evidence, revoke the temporary assignment/custom role, inspect the dedicated resource group, and confirm deletion explicitly. Deallocating the VM does not stop disk, NAT or public-IP charges.

Do not bypass the hook, delete a shared SRE Agent, or unregister providers as lab cleanup.

## Files and local validation

| File | Role |
|---|---|
| [azure.yaml](../azure.yaml) | Infrastructure-only `up` workflow and interactive lifecycle hooks |
| [infra/azd/main.bicep](../infra/azd/main.bicep) | Subscription-scoped group adapter calling the existing VM template |
| [infra/azd/main.parameters.json](../infra/azd/main.parameters.json) | Nonsecret azd-to-Bicep parameter mappings; no password |
| [scripts/azd/Common.ps1](../scripts/azd/Common.ps1) | Settings, target/inventory checks, deployment and readiness guards |
| [scripts/azd/preprovision.ps1](../scripts/azd/preprovision.ps1) | Account checks, approved provider changes, preflight, what-if and provisioning approval |
| [scripts/azd/postprovision.ps1](../scripts/azd/postprovision.ps1) | Guest readiness, approved initialization, tests and step-5 handoff |
| [tests/Test-Azd.ps1](../tests/Test-Azd.ps1) | Mocked automated-path checks; no Azure calls |

Run the [local validation commands](../Readme.md#validation) in PowerShell 7. The automated-path suite complements the guest/workflow regressions; it does not replace them. Honor signing policy and report compatibility skips as skips.

References checked October 28, 2026: [azd lifecycle hooks](https://learn.microsoft.com/azure/developer/azure-developer-cli/azd-extensibility), [environment variables](https://learn.microsoft.com/azure/developer/azure-developer-cli/manage-environment-variables), and the [azure.yaml schema](https://learn.microsoft.com/azure/developer/azure-developer-cli/azd-schema).

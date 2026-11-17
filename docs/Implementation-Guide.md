# Implementation guide

[Project README](../Readme.md) | [Architecture and execution flow](./Architecture-and-Execution-Flow.md) | [Agent testing](./SRE-Agent-Testing.md) | [Best practices and numbered skill setup](./SRE-Agent-Best-Practices-Guide.md)

**Updated:** November 17, 2026. Nonproduction Windows VM and synthetic logs only.

Use steps **1-7** once. Existing labs resume at the next unfinished step; do not reinstall or redeploy merely to repeat this guide. [Automated setup](./Automated-Setup.md) is an alternative for steps 1-4 on a separate lab.

**Choose one option per task:** **Option A: Using scripts** retains the package's existing commands. **Option B: Manually** provides operator-driven CLI, portal or VM-local actions without that task's workstation wrapper. Manual does not mean no PowerShell: guest initialization and reading still use the reviewed guest scripts. Where no automation exists, Option A says so; use Option B rather than inventing an API or treating setup as complete.

**Where to work:** Steps 1-3 run on your workstation or in Azure Portal. Step 4 distinguishes workstation, portal and VM-local commands. Steps 5-6 configure/use SRE Agent; step 7 verifies evidence and performs separately approved cleanup. These options are authored instructions, not new runtime validation. Neither option reads real SharePoint ULS logs.

**Already have a VM?** Start with [Existing VM and manual retest](#existing-vm-and-manual-retest). Do not redeploy the VM or run full cleanup merely to switch from Option A to Option B. VS Code is not required for the manual route.

**Keep this guide open while implementing.** Background diagrams and execution details are in [Architecture and execution flow](./Architecture-and-Execution-Flow.md); operating and extending the agent is covered in [Best practices](./SRE-Agent-Best-Practices-Guide.md).

## Contents

- [Existing VM and manual retest](#existing-vm-and-manual-retest)
- [Architecture and scope](#architecture-and-scope)
- [Prerequisites, permissions, and cost](#prerequisites-permissions-and-cost)
- [1. Select your account and target](#1-select-your-account-and-target)
- [2. Check prerequisites](#2-check-prerequisites)
- [3. Preview and deploy the lab](#3-preview-and-deploy-the-lab)
- [4. Create logs and test the reader](#4-create-logs-and-test-the-reader)
  - [4.1. Install the synthetic logs and reader](#41-install-the-synthetic-logs-and-reader)
  - [4.2. Prove manual retrieval](#42-prove-manual-retrieval)
  - [Optional realistic incident demo](#optional-realistic-incident-demo)
- [5. Configure SRE Agent access](#5-configure-sre-agent-access)
  - [5.1. Open or create the nonproduction agent](#51-open-or-create-the-nonproduction-agent)
  - [5.2. Complete the Basics fields](#52-complete-the-basics-fields)
  - [5.3. Review the configuration and deploy](#53-review-the-configuration-and-deploy)
  - [5.4. Confirm Review execution mode](#54-confirm-review-execution-mode)
  - [5.5. Copy the agent UAMI principal ID](#55-copy-the-agent-uami-principal-id)
  - [5.6. Connect only the lab resource scope](#56-connect-only-the-lab-resource-scope)
  - [5.7. Preview and grant the VM execution role](#57-preview-and-grant-the-vm-execution-role)
  - [5.8. Verify readiness before the first investigation](#58-verify-readiness-before-the-first-investigation)
- [6. Run the agent investigations](#6-run-the-agent-investigations)
- [7. Verify completion and clean up](#7-verify-completion-and-clean-up)
  - [Acceptance gates and evidence](#acceptance-gates-and-evidence)
  - [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [Moving to actual SharePoint logs](#moving-to-actual-sharepoint-logs)
- [Microsoft Learn references](#microsoft-learn-references)

## Existing VM and manual retest

**Already tested Option A? Keep the approved nonproduction VM and follow Option B in the linked steps. No VS Code terminal is required.**

1. **Skip new-VM setup (steps 1-3).** Confirm the correct Azure Windows VM, approved access, Running state and VM Agent readiness; retain existing networking.
2. **Copy and configure the guest files — [step 4.1](#41-install-the-synthetic-logs-and-reader), Option B, VM-local route.** Copy the two guest scripts, verify hashes, run the initializer in elevated PowerShell **on the VM**, and check the lab ACLs. Keep identical installed files; stop if they differ.
3. **Test remote retrieval — [step 4.2](#42-prove-manual-retrieval), Option B.** Use the portal and verify **2 positive matches / 0 negative-control matches**.
4. **Configure or verify agent access — [step 5](#5-configure-sre-agent-access), Option B.** Reuse the existing agent, UAMI and correct grants; do not duplicate them. To test manual reassignment, have the RBAC owner remove only the approved VM execution assignment using [Cleanup](#cleanup), retain its role definition, then reassign it in [step 5.7](#57-preview-and-grant-the-vm-execution-role). Do not run full cleanup or reset guest ACLs.
5. **Run fresh agent tests — [steps 5.8](#58-verify-readiness-before-the-first-investigation) and [6](#6-run-the-agent-investigations).** Verify readiness, approve each investigation and inspect actual results.
6. **Record results — [step 7](#acceptance-gates-and-evidence).** Identify reused setup separately from newly tested actions; defer cleanup while keeping the lab.

**Before customer sharing:** Complete the manual test and confirm customer host/access readiness. This walkthrough uses **synthetic logs only**; follow [Moving to actual SharePoint logs](#moving-to-actual-sharepoint-logs) before using real ULS files. Do not apply lab ACLs or lab-group deletion to the customer's SharePoint installation.

## Architecture and scope

User -> SRE Agent -> approved Run Command -> VM Agent -> hash-pinned reader -> local synthetic file -> bounded JSON evidence.

| Component | Configuration |
|---|---|
| VM | Windows Server 2022 Gen2, Trusted Launch, Standard SSD, persistent `C:` |
| Defaults | `eastus`, `Standard_D2s_v5`; select an approved available combination |
| Network | Private NIC, deny-inbound NSG, outbound NAT; no inbound file share |
| Collection | On demand; no streaming, SharePoint installation, MCP or ingestion |
| Monitoring | Agent monitoring is separate; VM files are not automatically ingested |

NAT is not an egress firewall. Run Command authorizes **arbitrary SYSTEM commands**, not read-only file access. If that authority is unacceptable, stop before the grant.

For diagrams, background communication, permission boundaries and how results become the summary, see [Architecture and execution flow](./Architecture-and-Execution-Flow.md). Continue below for the implementation steps.

## Prerequisites, permissions, and cost

- **Script/CLI routes:** Windows workstation with PowerShell 7, Azure CLI and Bicep installed through the approved process. This includes the manual new-VM template-compilation route.
- **Existing-VM portal/VM-local route:** No VS Code terminal or workstation `.ps1` execution is required. Use the approved package and independently supplied hashes, authorized Portal access and, if choosing VM-local setup, an approved elevated VM PowerShell session/file-transfer path. See [step 4.1](#41-install-the-synthetic-logs-and-reader).
- Approved public-cloud nonproduction subscription, region, provider/model, data handling and budget.
- Approved SYSTEM execution and evidence retention; no signing-policy bypass.
- Secrets remain in an approved store, not source, command arguments, screenshots or chat.

| Operator | Required authority |
|---|---|
| Deployment operator | Resource creation at approved scope; provider registration may require subscription authority |
| Setup/manual-test operator | VM, instance-view and extension-status reads, plus Run Command on this VM |
| RBAC owner | Role-definition write at the lab RG, role-assignment write on the VM and deployment permissions |
| SRE Agent Administrator | Agent configuration and approval of infrastructure actions |

VM, disk, NAT/IP, monitoring and agent/model charges can apply. Deallocation stops VM compute only.

Workstation readiness checks run as the CLI operator and include extension-status reads. They are separate from the agent's guest payload; do not broaden the agent runtime role to copy operator permissions.

## 1. Select your account and target

**Option A: Using scripts**

**Actions:** Open PowerShell 7 in the package root. Replace the example path; keep this terminal open.

```powershell
Set-Location -LiteralPath 'C:\path\to\azure-sre-agent-sharepoint-logs-lab'
$ErrorActionPreference = 'Stop'
$target = .\scripts\Initialize-LabContext.ps1 -SignIn
$location = 'eastus'
$vmSize = 'Standard_D2s_v5'
```

Enter approved tenant/subscription IDs when prompted. The [context helper](../scripts/Initialize-LabContext.ps1) defaults to generic names `rg-sp-sre-poc1` / `sp-sre-poc1`; pass `-ResourceGroupName` and `-VmName` for another new lab. Earlier customer-specific deployments are not automatically migrated; use a new isolated lab and retain the safety guards.

**Option B: Manually**

On your workstation, open PowerShell 7 in the extracted package root and keep that terminal open. Supply the approved directory/subscription interactively; never paste credentials into commands or this guide.

```powershell
Set-Location -LiteralPath 'C:\path\to\azure-sre-agent-sharepoint-logs-lab'
$ErrorActionPreference = 'Stop'
$tenantId = [guid](Read-Host 'Approved tenant ID')
$subscriptionId = [guid](Read-Host 'Approved nonproduction subscription ID')
az login --tenant $tenantId.ToString() --output none
if ($LASTEXITCODE -ne 0) { throw 'Sign-in failed; stop.' }
az account set --subscription $subscriptionId.ToString()
if ($LASTEXITCODE -ne 0) { throw 'Subscription selection failed; stop.' }
az account show --query '{tenant:tenantId,subscription:id,name:name,state:state,cloud:environmentName}' --output table
if ($LASTEXITCODE -ne 0) { throw 'Account verification failed; stop.' }
```

Verify the displayed tenant/subscription, `Enabled` state and `AzureCloud` against approval **before** defining the context below. Keep account output private. See [Azure CLI sign-in and subscription selection](https://learn.microsoft.com/cli/azure/authenticate-azure-cli-interactively).

```powershell
$target = @{
    SubscriptionId = $subscriptionId
    ResourceGroupName = 'rg-sp-sre-poc1'
    VmName = 'sp-sre-poc1'
}
$location = 'eastus'
$vmSize = 'Standard_D2s_v5'
```

Change names, region and size only to the approved values for a **new isolated lab**. This creates local variables, not resources. On any failure, stop and do not continue with a previous `$target`.

**Checkpoint:** Displayed account, tenant, subscription and VM match your approval. On failure, stop; do not reuse stale `$target`. In a new terminal, restore context before continuing.

## 2. Check prerequisites

**Option A: Using scripts**

**Actions:** Choose an approved region/size, then pass both explicitly:

```powershell
az bicep version
if ($LASTEXITCODE -ne 0) { throw 'Bicep is unavailable; install it through the approved process.' }
.\scripts\Test-Preflight.ps1 -SubscriptionId $target.SubscriptionId `
    -Location $location -VmSize $vmSize
```

For a restricted SKU, select another approved combination and rerun. There is no automatic region/SKU fallback.

**Option B: Manually**

1. On the workstation, run `az version` and `az bicep version`; stop on either failure and use your approved installation process.
2. In **Azure Portal > Subscriptions > approved subscription > Resource providers**, verify `Microsoft.Compute` and `Microsoft.Network` are **Registered**. Ask the subscription owner to register missing providers; do not register/unregister without approval. [Provider registration](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types#azure-portal).
3. Inspect the chosen size's full SKU metadata and regional usage:

   ```powershell
   az vm list-skus --subscription $target.SubscriptionId.ToString() `
       --location $location --size $vmSize --all --output json
   if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect SKU availability.' }
   az vm list-usage --subscription $target.SubscriptionId.ToString() `
       --location $location --output table
   if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect quota.' }
   ```

4. Find exactly one `virtualMachines` entry whose `name` equals `$vmSize`. Confirm no `Location` restriction, `HyperVGenerations` includes `V2`, and `TrustedLaunchDisabled` is not `True`. Record its `family` and `vCPUs`; verify both regional `cores` and that family's quota have at least that many free vCPUs. Stop if fields or quota are missing/unverified. This matches the [package preflight checks](../scripts/Test-Preflight.ps1); see [SKU metadata](https://learn.microsoft.com/cli/azure/vm#az-vm-list-skus) and [regional/family quota checks](https://learn.microsoft.com/azure/virtual-machines/quotas).
5. Resolve and record a fixed image version for step 3:

   ```powershell
   az vm image show --subscription $target.SubscriptionId.ToString() `
       --location $location `
       --urn 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest' `
       --query '{imageVersion:name,hyperVGeneration:hyperVGeneration}' --output json
   if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the Windows image.' }
   $imageVersion = Read-Host 'Exact published imageVersion from the result, not latest'
   ```

   Require `hyperVGeneration = V2` and a nonempty exact version, not `latest`. Do not guess missing values. See [image inspection](https://learn.microsoft.com/cli/azure/vm/image#az-vm-image-show).

Manual inspection does not run the automatic assertions. If any check is uncertain, stop or run Option A; an empty result is not success.

**Checkpoint:** Providers, image, quota and SKU checks pass. Preflight creates no resources and does not reserve capacity.

## 3. Preview and deploy the lab

**Option A: Using scripts**

**Actions:** For a **new lab only**, create a dedicated group. Do not adopt or retag a shared group.

```powershell
.\scripts\New-LabResourceGroup.ps1 -SubscriptionId $target.SubscriptionId `
    -ResourceGroupName $target.ResourceGroupName -Location $location
.\scripts\Deploy-Lab.ps1 @target -Location $location -VmSize $vmSize -Mode Preview
```

After approving the target, changes and costs:

```powershell
.\scripts\Deploy-Lab.ps1 @target -Location $location -VmSize $vmSize -Mode Deploy
```

Use the masked password prompts; input may be requested again for deployment. On failure, inspect partial state before retrying.

**Option B: Manually**

Use the **same reviewed infrastructure template**, deployed by the operator in Azure Portal. This avoids replacing the private lab design with default VM/network settings. It is manual deployment, not hand-authoring a second design.

1. Complete step 2. In **Azure Portal > Resource groups > Create**, select the approved subscription, a **new dedicated** group matching `$target.ResourceGroupName`, and the approved region. Add tags `purpose = SP-SRE-POC1` and `environment = nonproduction`; review and create. If that group already exists, stop and verify ownership/disposability; do not adopt or retag a shared group. [Create a resource group](https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-portal#create-a-resource-group).
2. On the workstation, compile the unchanged [main.bicep](../infra/main.bicep) to a temporary ARM JSON file:

   ```powershell
   $manualTemplate = Join-Path ([IO.Path]::GetTempPath()) "sp-sre-main-$([guid]::NewGuid()).json"
   az bicep build --file .\infra\main.bicep --outfile $manualTemplate
   if ($LASTEXITCODE -ne 0) { throw 'Template compilation failed; stop.' }
   $manualTemplate
   ```

   Compilation does not deploy resources or supply an administrator password. See [Bicep build](https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-cli#build).
3. In Azure Portal, search **Deploy a custom template > Build your own template in the editor**. Load the compiled JSON file and save. Select the approved subscription and dedicated lab RG. [Custom-template deployment](https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-portal#deploy-resources-from-custom-template).
4. Set `vmName`, `location`, `vmSize`, and `adminUsername` to the approved values (`pocadmin` is the package default username). Set `imageVersion` to the exact version verified in step 2. Keep the template's lab tags. Enter the approved VM password **only in the secure parameter field**; do not save/download completed parameter files or put the password in chat.
5. Review [main.bicep](../infra/main.bicep) and the compiled template: private NIC without a public IP; `10.74.0.0/24` VNet and `10.74.0.0/26` lab subnet; subnet NSG denying all inbound at priority 100; NAT gateway with its egress public IP; Windows Server 2022 Gen2; Trusted Launch with Secure Boot/vTPM; Standard SSD; VM Agent enabled; correct lab tags. These are **package configuration requirements**, not a claim that NAT filters outbound destinations.
6. Portal validation/review is **not ARM what-if**. Before creation, obtain owner approval of the template, exact target and costs. If your process requires a what-if change preview, use Option A for this step; do not substitute the portal review page.
7. Deploy once, wait for **Succeeded**, and inspect the deployed resources. In **VM > Overview/Properties**, verify the private target and Running state; inspect **VM > Extensions + applications** and VM Agent status for successful/Ready state before executing anything. Stop if an extension is failed or still provisioning. Run Command requires a ready VM Agent; see [restrictions](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#restrictions).
8. Remove only the temporary compiled file after review/deployment: `Remove-Item -LiteralPath $manualTemplate`. Keep sanitized deployment evidence privately; investigate partial resources before any retry.

**Checkpoint:** Deployment `Succeeded`; private VM is running and VM Agent is ready. A preview or declined deployment is not completion.

## 4. Create logs and test the reader

### 4.1. Install the synthetic logs and reader

**Option A: Using scripts**

**Actions:** Approve the SYSTEM installation on the verified VM:

```powershell
.\scripts\Initialize-Lab.ps1 @target
```

Creates `Synthetic-ULS.log` and `Read-UlsLab.ps1` under **VM path** `C:\SP-SRE-Lab`, with SYSTEM/Administrators permissions. Do not execute guest-only scripts on the workstation. Identical files are retained; changed files are refused.

**Option B: Manually**

The [initializer](../scripts/Initialize-UlsLab.ps1) is the guest setup payload; the [reader](../scripts/Read-UlsLab.ps1) later reads the log. Choose **one** manual execution location; do not install twice.

**Portal route (no desktop access or file copy needed):**

1. **Preparation only - workstation PowerShell, from the approved package root:** Calculate the reader payload and reference hash. This prepares values; the initializer executes on the VM through the portal in items 3-4, not on the workstation.

   ```powershell
   $readerBytes = [IO.File]::ReadAllBytes((Join-Path (Get-Location).Path 'scripts\Read-UlsLab.ps1'))
   $readerBase64 = [Convert]::ToBase64String($readerBytes)
   $approvedReaderHash = (Get-FileHash .\scripts\Read-UlsLab.ps1 -Algorithm SHA256).Hash
   $readerBase64
   $approvedReaderHash
   ```

2. Open **Azure Portal > approved lab VM > Run command > RunPowerShellScript**. Confirm subscription, RG, VM, lab tags, Windows OS, Running state and VM Agent readiness. This is **Action Run Command**, not a new managed Run Command resource. The operator requires the setup/manual-test permissions listed above, plus subscription-level `Microsoft.Compute/locations/runCommands/read` to list/open the command in the portal; have the access owner verify existing access rather than broadening the agent's VM role. [Portal execution](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#using-run-commands) and [command-listing permissions](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#limiting-access-to-run-command).
3. Paste the complete contents of [Initialize-UlsLab.ps1](../scripts/Initialize-UlsLab.ps1) into the editor **inside a script block** as shown below. Replace the middle comment with the complete initializer, including its `param` block; replace `<READER_BASE64>` with the Base64 value from step 1 (not the hash). This supplies the mandatory parameter without an interactive prompt or relying on a custom-parameter control in the portal. Do not paste the workstation wrapper or a workstation file path.

   ```powershell
   & {
       # Replace this comment with the COMPLETE Initialize-UlsLab.ps1 contents.
   } -ReaderBase64 '<READER_BASE64>'
   ```
4. Obtain approval for SYSTEM installation, then select **Run** once. Review stdout and stderr. Require the initialization JSON and compare `readerSha256` to `$approvedReaderHash`. Errors, timeouts or a mismatched hash are failures; inspect command state before retrying. Windows Action Run Command runs as SYSTEM and requires working agent connectivity; see [restrictions](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#restrictions).

**VM-local route (only if an approved administrative session and file-transfer path already exist):**

- [Initialize-UlsLab.ps1](../scripts/Initialize-UlsLab.ps1): Run in item 3 below to create the synthetic log, install the reader and configure lab folder/file permissions.
- [Read-UlsLab.ps1](../scripts/Read-UlsLab.ps1): Installed, not executed, during setup; run in step 4.2 to find a correlation ID in the synthetic log and return bounded JSON evidence.

1. The default lab denies inbound access. Do **not** open RDP/SMB/WinRM or change NSGs just to follow this route; use the portal route if no approved session exists.
2. Using the approved transfer method, copy **both** [Initialize-UlsLab.ps1](../scripts/Initialize-UlsLab.ps1) and [Read-UlsLab.ps1](../scripts/Read-UlsLab.ps1) to `C:\Temp\SP-LabSetup` **on the VM**. Compare their SHA-256 hashes with the original package before execution. Honor signing policy; do not bypass it merely to run them.

   **Browser Bastion: Explorer file paste is not supported.** Bastion's web clipboard transfers text only; browser clipboard permission does not enable file transfer. See [Bastion text clipboard](https://learn.microsoft.com/azure/bastion/bastion-vm-copy-paste). For these two small synthetic-lab scripts, the proposed package helper transfers their bytes as reviewed text, not as a Bastion file-upload feature:

   - On your **workstation**, from the approved package root in **PowerShell 7**, generate a new transfer script with [New-LabSetupTransfer.ps1](../scripts/New-LabSetupTransfer.ps1):

     ```powershell
     $transfer = Join-Path $env:TEMP ("Stage-LabFiles-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
     $transferInfo = .\scripts\New-LabSetupTransfer.ps1 -OutputPath $transfer
     $transferInfo.files | Format-Table name, sha256
     notepad.exe $transfer
     ```

   - Review the generated text. It embeds only the two setup files and their original SHA-256 hashes. It stages them at the fixed VM path, keeps identical files and refuses different files or reparse-point destinations. It does **not** execute the initializer, create synthetic logs, change ACLs/networking, call Azure or grant agent access. Base64 preserves bytes; it is not encryption. Use only the approved synthetic package, never secrets or customer logs.
   - If clipboard transfer is approved, copy the **text** on the workstation:

     ```powershell
     Get-Content -LiteralPath $transfer -Raw | Set-Clipboard
     ```

     [Set-Clipboard](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/set-clipboard) replaces your local clipboard. In the **VM's** Notepad, paste the text and save it as `C:\Temp\Stage-LabFiles.ps1` with **Save as type: All Files**, not `.ps1.txt`. The `C:\Temp` parent must be an approved normal directory. Browser clipboard permission must be allowed for the Bastion page; where needed, use its left-side **>>** clipboard palette. If clipboard access is prohibited by organizational policy, stop and use the approved portal route above; do not bypass the restriction.
   - Under the approved signing policy, run the generated script from elevated **Windows PowerShell inside the VM**:

     ```powershell
     & 'C:\Temp\Stage-LabFiles.ps1'
     Get-FileHash -LiteralPath 'C:\Temp\SP-LabSetup\Initialize-UlsLab.ps1',
         'C:\Temp\SP-LabSetup\Read-UlsLab.ps1' -Algorithm SHA256
     ```

     Require `kind = uls-lab-files-staged`, exactly the two named files, and hashes matching `$transferInfo.files` from the workstation. If signing is required, obtain approved signatures/release instructions; do not disable execution policy or paste commands to evade signing. Truncated text, a hash mismatch or an existing different file is a failure, not a reason to overwrite. Inspect partial state before retrying.
   - Continue with step 3 below **on the VM**. Staging alone is not initialization or a successful log read.

3. Open an **elevated PowerShell session inside the VM** and run:

   ```powershell
   Set-Location 'C:\Temp\SP-LabSetup'
   $ErrorActionPreference = 'Stop'
   $readerBytes = [IO.File]::ReadAllBytes((Join-Path (Get-Location).Path 'Read-UlsLab.ps1'))
   $readerBase64 = [Convert]::ToBase64String($readerBytes)
   .\Initialize-UlsLab.ps1 -ReaderBase64 $readerBase64
   Get-FileHash -LiteralPath 'C:\SP-SRE-Lab\Read-UlsLab.ps1' -Algorithm SHA256
   ```

4. Require the initialization JSON and verify the installed hash against the approved package hash, not merely against another VM copy.

5. **Test folder/file permissions (read-only):** Run this command in the same elevated VM session. It displays the accounts, rights and inheritance for all three paths; it does not change permissions.

   ```powershell
   $ErrorActionPreference = 'Stop'
   foreach ($path in @('C:\SP-SRE-Lab', 'C:\SP-SRE-Lab\Synthetic-ULS.log', 'C:\SP-SRE-Lab\Read-UlsLab.ps1')) {
       Write-Output "ACL: $path"
       $acl = Get-Acl -LiteralPath $path
       $acl | Format-List Owner,AreAccessRulesProtected
       $acl.Access | Format-List IdentityReference,FileSystemRights,AccessControlType,IsInherited,InheritanceFlags,PropagationFlags
   }
   ```

   Expand the rules as above; object type names alone do not verify accounts or rights. [Get-Acl reference](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/get-acl?view=powershell-5.1), checked November 17, 2026.

   **Expected results** from the [initializer's ACL contract](../scripts/Initialize-UlsLab.ps1):

   | Path | AreAccessRulesProtected | IsInherited for each rule |
   |---|---|---|
   | `C:\SP-SRE-Lab` | `True` | `False` |
   | `C:\SP-SRE-Lab\Synthetic-ULS.log` | `False` | `True` |
   | `C:\SP-SRE-Lab\Read-UlsLab.ps1` | `False` | `True` |

   Each path must have only two access entries: SYSTEM (`S-1-5-18`) and built-in Administrators (`S-1-5-32-544`), both with `FileSystemRights = FullControl` and `AccessControlType = Allow`. Check all three paths; folder output alone is not full verification. Stop on a mismatch.

   Do not grant the agent UAMI a Windows folder ACL for this SYSTEM execution path, and do not apply these lab ACLs to real SharePoint folders. [Windows Run Command execution identity](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#restrictions).

Both routes create `C:\SP-SRE-Lab\Synthetic-ULS.log` with three synthetic records and install `C:\SP-SRE-Lab\Read-UlsLab.ps1`, with SYSTEM/Administrators ACLs. The initializer retains identical files but refuses changed files; do not remove/overwrite them to get past a failure. It does not install SharePoint, collect real logs or grant SRE Agent access.

**No workstation PowerShell available:** Obtain the original package hashes from the approved release owner through the trusted sharing channel; compare the transferred files using `Get-FileHash` inside the VM. Use that approved reader hash in steps 4.2 and 6 instead of running their workstation hash commands. A hash calculated only from an unverified VM copy is not an independent integrity check. No VS Code terminal or workstation `.ps1` execution is required.

**Checkpoint:** `kind = uls-lab-initialized`, `synthetic = true`, returned reader hash matches the approved package, and folder/file ACLs match the table above. Then continue to [step 4.2](#42-prove-manual-retrieval); initialization alone does not verify retrieval or agent execution.

### 4.2. Prove manual retrieval

**Purpose:** Verify the installed reader and expected synthetic-log results. Prepare the reference hash on the workstation; execute the test inside the VM or through Azure Portal, not directly on the workstation. No VS Code terminal is required.

**Option A: Using scripts**

**Actions (workstation PowerShell):** This wrapper invokes the VM remotely; it is not the VM-local payload shown in Option B.

```powershell
.\scripts\Test-Lab.ps1 @target
```

The call chain is [Test-Lab.ps1](../scripts/Test-Lab.ps1) -> [Get-LabEvidence.ps1](../scripts/Get-LabEvidence.ps1) -> Action Run Command -> installed [Read-UlsLab.ps1](../scripts/Read-UlsLab.ps1) -> synthetic log.

**Option B: Manually**

1. **Prepare the reference hash - workstation only.** Use standalone PowerShell to read the **approved original** reader file. Replace the example below with its full workstation path; no folder change is needed. This calculates a hash, not a log-retrieval test. Reuse an already verified reference hash, or obtain it from the approved release owner if workstation PowerShell is unavailable.

   ```powershell
   (Get-FileHash -LiteralPath 'C:\path\to\approved-package\scripts\Read-UlsLab.ps1' -Algorithm SHA256).Hash
   ```

2. **Execute the test - choose one location below.** Replace `<APPROVED_READER_SHA256>` with the reference hash from item 1 before running. **Do not run this payload in your laptop/workstation PowerShell:** its paths refer to files on the VM.

   - **VM-local:** Paste it into the approved elevated PowerShell session **inside the VM**. This tests local reader behavior only.
   - **Portal:** Paste it into **Azure Portal > verified lab VM > Run command > RunPowerShellScript**, approve the exact VM/payload, then select **Run** once. This also tests remote transport.

   ```powershell
   $ErrorActionPreference = 'Stop'
   $reader = 'C:\SP-SRE-Lab\Read-UlsLab.ps1'
   if ((Get-FileHash -LiteralPath $reader -Algorithm SHA256).Hash -ne '<APPROVED_READER_SHA256>') {
       throw 'Installed reader differs from the approved package.'
   }
   & $reader -CorrelationId '11111111-1111-1111-1111-111111111111'
   ```

   > [!NOTE]
   > **Preserve the script's line breaks when pasting into Portal.** Confirm `$ErrorActionPreference`, `$reader`, `if` and the final invocation remain separate statements before selecting Run. Joined text such as `'Stop' $reader` is not valid PowerShell. A "Script execution complete" banner is not success if the output contains parser errors.

3. **Check the positive result.** Inspect console output/errors for VM-local execution, or stdout **and** stderr for the portal. Require `kind = uls-lab-evidence`, `synthetic = true`, the correct `source`, `file = C:\SP-SRE-Lab\Synthetic-ULS.log`, requested `correlationId`, fresh UTC `queryUtc`, `matchingRecordsReturned = 2`, `partial = false`, and two evidence records with line numbers. Stop on any error or hash mismatch; reconcile the approved package and installed version rather than removing the check or substituting the VM's hash.
4. **Run the negative control in the same execution location.** Change **only** the correlation ID to `33333333-3333-3333-3333-333333333333`. Require the same source/contract, `matchingRecordsReturned = 0`, `partial = false` and an empty `evidence` array. A failed command is not a zero-match result.
5. **Before agent testing:** If you tested only inside the VM, repeat both controls through the portal or use Option A to verify remote transport. Local success does not satisfy this gate.

The portal route verifies operator-driven remote transport, not SRE Agent execution or its UAMI. [Action Run Command portal workflow](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#using-run-commands).

**Checkpoint:** Exactly **2** positive matches and **0** absent-control matches, `partial = false`, correct VM/file and no errors. This verifies manual transport, not agent execution.

Smoke-reader limits: one file, 1 MiB, 10,000 lines, 3 matches, 180 characters per fragment and 2,500 UTF-8 output bytes. Shortening is not redaction.

### Optional realistic incident demo

**Option A: Using scripts**

Use the separate [incident walkthrough](./Incident-Demo.md) to install and test 638 events without changing the smoke fixture. It has its own reader, prompt generator and pagination contract. Do not repeat an already verified installation.

**Option B: Manually**

This optional dataset is **not** the three-record smoke fixture. Use this route only if an approved administrative session and file-transfer method already exist; do not open inbound access to enable it. Otherwise retain Option A. The [incident walkthrough](./Incident-Demo.md) owns the scenario/page contract.

1. Copy [Initialize-IncidentDemoGuest.ps1](../scripts/Initialize-IncidentDemoGuest.ps1), [Read-IncidentDemo.ps1](../scripts/Read-IncidentDemo.ps1), and [SharePoint-IncidentDemo-v1.tsv](../data/SharePoint-IncidentDemo-v1.tsv) into `C:\Temp\SP-IncidentSetup` **on the lab VM**, preserving exact bytes. Compare all three hashes with the original package before execution. Record the original dataset and reader SHA-256 values privately.
2. In elevated PowerShell **inside the VM**, prepare the same compressed package expected by the guest initializer:

   ```powershell
   Set-Location 'C:\Temp\SP-IncidentSetup'
   $ErrorActionPreference = 'Stop'
   $data = [IO.File]::ReadAllBytes((Join-Path (Get-Location).Path 'SharePoint-IncidentDemo-v1.tsv'))
   if ($data.Length -eq 0 -or $data.Length -gt 1MB) { throw 'Invalid dataset size.' }
   $memory = [IO.MemoryStream]::new()
   try {
       $gzip = [IO.Compression.GZipStream]::new($memory, [IO.Compression.CompressionMode]::Compress, $true)
       try { $gzip.Write($data, 0, $data.Length) } finally { $gzip.Dispose() }
       $dataBase64 = [Convert]::ToBase64String($memory.ToArray())
   }
   finally { $memory.Dispose() }
   $readerBytes = [IO.File]::ReadAllBytes((Join-Path (Get-Location).Path 'Read-IncidentDemo.ps1'))
   $readerBase64 = [Convert]::ToBase64String($readerBytes)
   if ($dataBase64.Length + $readerBase64.Length -gt 24000) { throw 'Encoded package exceeds the reviewed budget.' }
   .\Initialize-IncidentDemoGuest.ps1 -DataGzipBase64 $dataBase64 -ReaderBase64 $readerBase64
   ```

3. Require `kind = uls-incident-demo-initialized`, `synthetic = true`, `datasetVersion = v1`, the paths below, and `datasetSha256`/`readerSha256` equal to the **original package** hashes. The guest initializer retains identical files, refuses different files, and applies SYSTEM/Administrators ACLs. The smoke files remain unchanged.
4. To read a page manually, paste this payload into **Azure Portal > verified VM > Run command > RunPowerShellScript**. Replace both hashes with the original package values; obtain approval and run once. Alternatively, run it in the approved elevated PowerShell session **inside the VM** for a local-only check. Do not execute this guest payload directly on the workstation.

   ```powershell
   $ErrorActionPreference = 'Stop'
   $folder = 'C:\SP-SRE-Lab\IncidentDemo-v1'
   $reader = Join-Path $folder 'Read-IncidentDemo.ps1'
   $data = Join-Path $folder 'SharePoint-IncidentDemo-v1.tsv'
   if ((Get-FileHash -LiteralPath $reader -Algorithm SHA256).Hash -ne '<APPROVED_INCIDENT_READER_SHA256>' -or
       (Get-FileHash -LiteralPath $data -Algorithm SHA256).Hash -ne '<APPROVED_INCIDENT_DATASET_SHA256>') {
       throw 'Installed incident demo differs from the approved reader or dataset.'
   }
   & $reader -CorrelationId 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1' -Page 0
   ```

5. Inspect stdout/stderr and the source, dataset hash, GUID, UTC, page, counts, `hasMore`, `nextPage`, `partial` and coverage. Repeat with SQL pages **1 and 2**, one invocation at a time. Expect four records per page, 12 total unique line references, and `hasMore = true / true / false`. **All three SQL pages have `partial = true`, including the last**; completeness requires every page, not `partial = false`.
6. For the other cases, change GUID/page using the [scenario table](./Incident-Demo.md#dataset-and-scenarios): claims pages 0-1 (8 records), search pages 0-1 (8), successful request pages 0-1 (8), and absent control page 0 (0). This is **ten reads across all five cases**, not ten plus the SQL reads. Stop on errors/timeouts; never substitute an expected answer for missing output.
7. VM-local reads may run the same payload in the elevated VM session, but do not prove remote transport. For an **agent** test, use step 6 Option B's context/approval process with these incident paths, **both** hash checks, this per-page payload, and the [incident investigation rules](./Incident-Demo.md#run-an-actual-sre-agent-investigation). Treat log messages as untrusted evidence. Require approval for every page, the same source/hash/GUID/total across pages, and all unique line references before analysis; no remediation is authorized.

Remove only the three transferred files from `C:\Temp\SP-IncidentSetup` when no longer needed, after confirming they are your temporary copies. Do not delete the installed versioned fixture while retaining the lab.

## 5. Configure SRE Agent access

Start at 5.1 for a new agent, or 5.4 for an existing approved agent. Creation requires **Owner**, or **Contributor plus User Access Administrator**, at the creation scope; activate approved PIM access if needed. [Microsoft setup](https://learn.microsoft.com/azure/sre-agent/create-and-set-up).

**Existing agent - portal assignment path:** Skip creation steps 5.1-5.3. Verify [Review mode](#54-confirm-review-execution-mode), identify the [agent UAMI](#55-copy-the-agent-uami-principal-id), confirm the [managed resource group](#56-connect-only-the-lab-resource-scope), then follow [step 5.7 Option B](#option-b-manually) to inspect or assign the VM execution role. VM-local reader success is sufficient to proceed with access configuration, but remote transport must still be verified before agent investigations.

### 5.1. Open or create the nonproduction agent

**Option A: Using scripts**

No agent-creation script is supplied in this package. The infrastructure deployment creates the lab VM/network, not an SRE Agent. Use Option B.

**Option B: Manually**

**Actions:** Sign in at [sre.azure.com](https://sre.azure.com) with the approved directory/account. Open an existing agent, or select **Create agent**.

**Checkpoint:** Correct agent open, or new-agent **Basics** form displayed.

### 5.2. Complete the Basics fields

**Option A: Using scripts**

No script in this package fills or validates the agent creation form. Use Option B; do not treat VM deployment settings as agent settings.

**Option B: Manually**

| Field | Selection |
|---|---|
| Subscription | Approved nonproduction subscription |
| Resource group | Separate agent RG, not the VM lab RG |
| Agent name / region | Unique lab name and currently available approved region |
| Provider / model | Organization-approved selection; review processing terms and charges |
| User-assigned managed identity | **Create new**, or deliberately select an approved existing UAMI |
| Application Insights | Create new unless an approved instance should be reused |

**Actions:** Complete all required fields. Empty **Use existing** identity selection blocks Next. Do not assume one provider's region/data-boundary terms apply to another.

**Checkpoint:** Settings approved; required fields complete; Next enabled.

### 5.3. Review the configuration and deploy

**Option A: Using scripts**

No agent-deployment script is supplied. Use Option B and retain the separate approval for agent resources/costs.

**Option B: Manually**

**Actions:** Review subscription, RG, region, provider, identity and monitoring. After owner approval, deploy once, wait for completion and select **Set up your agent**.

The agent, UAMI, role assignments and monitoring are distinct resources. Application Insights/workspace support agent monitoring; they do not automatically ingest VM files.

**Checkpoint:** Deployment succeeds and the agent opens with your SRE Agent Administrator access. Provisioning success is not proof of VM execution.

### 5.4. Confirm Review execution mode

**Option A: Using scripts**

No run-mode configuration script is supplied. The investigation prompt requests Review, but prompt text is not configuration verification. Use Option B.

**Option B: Manually**

**Actions:** Open **Settings > Basics** and confirm **Review**. This is execution mode, not the wizard's Review page. If using a plan/task, its autonomy setting can override the default; set that to Review too.

**Checkpoint:** Infrastructure actions require authorized approval. If the setting is unavailable, contact the agent administrator. [Run modes](https://learn.microsoft.com/azure/sre-agent/run-modes).

### 5.5. Copy the agent UAMI principal ID

**Option A: Using scripts**

No identity-discovery script is supplied. [Grant-AgentAccess.ps1](../scripts/Grant-AgentAccess.ps1) consumes a verified principal ID; it does not select the correct agent identity for you. Use Option B.

**Option B: Manually**

**Actions:** In the agent, open **Settings > General**, find **Azure settings > Managed identity**, and select **Go to Identity**. Some versions show **Settings > Azure settings > Managed Identity** directly. On the linked UAMI, copy **Object (principal) ID**. [Find the agent UAMI](https://learn.microsoft.com/azure/sre-agent/agent-identity#find-your-agents-uami).

Use this UAMI for the VM grant, **not** its client ID, the system-assigned identity, the VM identity or your user account. Runtime uses managed identity without storing your password. The RBAC owner's CLI sign-in is a separate, one-time setup identity.

**Checkpoint:** Exact agent UAMI principal GUID copied. [Agent identity](https://learn.microsoft.com/azure/sre-agent/agent-identity).

### 5.6. Connect only the lab resource scope

**Option A: Using scripts**

No managed-resource onboarding script is supplied. Granting the custom VM role in step 5.7 does not replace agent resource-scope configuration. Use Option B.

**Option B: Manually**

**Actions:** In the agent, open **Build + Set up > Managed resources > Add resource group**. Labels can vary by portal version.

1. Select the **VM lab RG checkbox**, not the agent RG or whole subscription.
2. Select **Reader**, not **Privileged**. Have the RBAC owner review every proposed role and scope.
3. On **View agent permissions**, select **Add resource group**; wait for propagation.

**Needed** means pending permission. Environment-specific portal screenshots are intentionally omitted from this package.

On the initial setup page, the alternative is **Quickstart > Azure resources > Add resources > Resource group**. Use one path, not both; do not recreate an agent to find the menu.

The current documented navigation can also appear as **Build + setup > Context > Managed resources > Add resource group**, followed by **Save**. Use the labels present in your portal and verify the resulting lab RG and Reader level; do not add the same group twice. [Managed-resource setup](https://learn.microsoft.com/azure/sre-agent/manage-permissions#add-managed-resource-groups).

**Checkpoint:** Lab RG appears in Managed resources. Reader onboarding does not grant Run Command or remove inherited privileges. [Current management reference](https://learn.microsoft.com/azure/sre-agent/manage-permissions#add-managed-resource-groups).

### 5.7. Preview and grant the VM execution role

**Choose one method:** [Option A: Using scripts](#option-a-using-scripts) or [Option B: Manually](#option-b-manually). Both use the same three permissions with a VM-only assignment. Existing agents complete the checks in steps 5.4-5.6; steps 5.1-5.3 apply only when creating an agent. Inspect existing assignments and do not duplicate a correct grant.

<a id="option-b---powershell-script"></a>
#### Option A: Using scripts

**Actions:** The RBAC owner uses the verified **VM** `@target`. In a separate terminal, repeat step 1 with that owner's account.

Paste the UAMI **Object (principal) ID** at the prompt:

```powershell
$agentPrincipal = Read-Host 'Approved agent UAMI Object (principal) ID'
.\scripts\Grant-AgentAccess.ps1 @target -AgentPrincipalId $agentPrincipal -Mode Preview
```

After reviewing the principal, exact VM, effective access and SYSTEM authority:

```powershell
.\scripts\Grant-AgentAccess.ps1 @target -AgentPrincipalId $agentPrincipal -Mode Deploy
```

**Checkpoint:** For the script method, deployment `Succeeded`. In **VM > Access control (IAM) > Role assignments**, search **SP SRE POC1 Run Command**. Confirm **Type = Managed identity**, **Scope = This resource**, and the matching Object/principal ID. Review inherited access and allow propagation; do not add duplicate assignments.

The [role template](../infra/agent-access.bicep) permits VM read, instance-view read and Run Command. Its definition is RG-assignable; the assignment is VM-only. This still permits arbitrary **SYSTEM execution**.

<a id="option-a---azure-portal"></a>
#### Option B: Manually

**Prerequisites:** The RBAC owner needs authority to create custom roles at the lab resource-group scope and assign roles on the VM. See [custom-role prerequisites](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#prerequisites) and [role-assignment prerequisites](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal#prerequisites). Have the approved VM/resource group and the agent UAMI's **Object (principal) ID** from [step 5.5](#55-copy-the-agent-uami-principal-id) ready.

**1. Find or create the custom role at the lab resource group**

If Option A previously created the role, inspect **VM > Access control (IAM) > Role assignments** and the lab RG's **IAM > Roles** first. Verify the role's permissions, assignable scope and intended UAMI assignment; do not rely on its name alone. If the correct VM assignment already exists, retain it and go to verification below. If only the approved role definition exists, reuse it and continue to **2. Assign the role on the specific VM**. Create a role below only when no suitable approved role exists. [Inspect custom roles](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#list-custom-roles).

Follow the [Azure Portal custom-role procedure](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#start-from-scratch):

1. Open **Resource groups > your VM lab resource group > Access control (IAM) > Add > Add custom role**.
2. On **Basics**, set **Baseline permissions = Start from scratch**. Use a directory-unique name such as `SP SRE POC1 Run Command - <unique-lab-suffix>` and description `Privileged SYSTEM command execution on the approved lab VM; not a read-only file role`. [Role naming](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#step-3-basics).
3. On **Permissions > Add permissions**, find **Microsoft.Compute** and select only the following **Actions**, matching the [lab role template](../infra/agent-access.bicep):

   ```text
   Microsoft.Compute/virtualMachines/read
   Microsoft.Compute/virtualMachines/instanceView/read
   Microsoft.Compute/virtualMachines/runCommand/action
   ```

4. On **Assignable scopes**, retain **only the VM lab resource group**, not the subscription. This makes the role available for assignment within the group; it does not grant access by itself. [Assignable scopes](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#step-5-assignable-scopes).
5. On **JSON**, verify the three exact Actions, empty `notActions`, `dataActions` and `notDataActions`, and only the approved resource group in `assignableScopes`. Select **Review + create**, review and then **Create**. [JSON review](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#step-6-json).

**2. Assign the role on the specific VM**

Follow the [Azure Portal role-assignment procedure](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal):

1. Open **Virtual machines > your approved VM > Access control (IAM) > Add > Add role assignment**. Do not start this assignment from the resource group or subscription.
2. On **Role**, search for and select the custom role created above.
3. On **Members**, choose **Managed identity > Select members**. Select the subscription containing the agent identity, choose **User-assigned managed identity**, then select the **SRE Agent's UAMI**, not the VM identity or your user account. Verify its Object (principal) ID against step 5.5. [Managed-identity selection](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal#step-4-select-who-needs-access).

   > [!NOTE]
   > **Select the SRE Agent's USER-ASSIGNED managed identity (UAMI), not its system-assigned identity.** In the identity picker, explicitly choose **User-assigned managed identity** and match the selected identity's full **Object (principal) ID** with step 5.5 before saving. Do not select the agent service instance merely because its display name matches. The UAMI is used for Azure resource operations; the system-assigned identity serves internal infrastructure. [Agent identity](https://learn.microsoft.com/azure/sre-agent/agent-identity#what-gets-created).

4. On **Review + assign**, confirm the exact role, intended UAMI and **specific VM scope**. Only after owner approval, select the final **Review + assign**. These are manual review checkpoints, not an ARM/Bicep what-if preview. [Assignment review](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal#step-7-assign-role).

**3. Verify and continue**

In **VM > Access control (IAM) > Role assignments**, confirm the custom role, intended UAMI, **Type = Managed identity** and **Scope = This resource**. Review inherited access as well; the new VM-scoped grant does not remove other access. Then continue to [step 5.8](#58-verify-readiness-before-the-first-investigation). Successful assignment alone is not agent acceptance. [Assignment scopes](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal#step-1-identify-the-needed-scope).

**Safety:** Action Run Command permits privileged commands, and Windows scripts run as **SYSTEM**. This is not read-only log access. Retain the agent's Review-mode approval requirement; do not substitute a broader role for convenience. [Run Command permissions](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#limiting-access-to-run-command) and [execution restrictions](https://learn.microsoft.com/azure/virtual-machines/windows/run-command#restrictions).

**Portal cleanup:** Record the role/assignment IDs privately and follow the [portal-created grant cleanup](#cleanup), not the scripted deployment-output commands.

**References checked November 16, 2026:** [Create a custom role](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal) | [Assign a role](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal) | [Windows Action Run Command](https://learn.microsoft.com/azure/virtual-machines/windows/run-command). Portal steps are documentation guidance, not a record of execution in your environment.

### 5.8. Verify readiness before the first investigation

**Option A: Using scripts**

Run [Test-Lab.ps1](../scripts/Test-Lab.ps1) as in step 4.2 if remote transport has not yet been verified. This verifies the operator path only; no script in this package verifies all agent configuration/tool/UAMI gates. Complete Option B as well before the first investigation.

**Option B: Manually**

**Actions:** Confirm 5.4-5.7, an available Azure execution tool, and the intended UAMI. RBAC alone does not enable a tool. Configure [reusable context](./SRE-Agent-Testing.md#configure-reusable-context) if users should ask short questions.

1. Confirm the lab RG is managed, the VM-only grant targets the agent UAMI, and inherited access has been reviewed.
2. Confirm Review mode, including any response-plan/task override.
3. Follow the [reusable-context instructions](./SRE-Agent-Testing.md#configure-reusable-context) to select the required Azure execution tool(s), or verify that the approved conversation already has them.
4. Prepare the exact VM resource ID, fixed reader path and current package hash for step 6. Do not use a screenshot's old hash or assume a local VS Code file is visible to the agent.

**Checkpoint:** Ready to test, not automatically accepted. An OBO request uses the user's permissions; do not silently substitute it for proving the UAMI path.

## 6. Run the agent investigations

**Option A: Using scripts**

On the workstation, generate the bootstrap text with the verified target:

```powershell
.\scripts\New-AgentPrompt.ps1 @target `
    -CorrelationId '33333333-3333-3333-3333-333333333333'
```

Follow [SRE Agent testing](./SRE-Agent-Testing.md) for the single authoritative procedure: supply context once, ask short questions, review the exact payload, and inspect fresh tool results.

The generator produces **text only**. Paste its entire output into SRE Agent; generating it does not invoke Azure or read a file. The execution chain is SRE Agent -> approved Action Run Command -> installed [Read-UlsLab.ps1](../scripts/Read-UlsLab.ps1) -> synthetic log. It does not call the initializer during an investigation.

**Option B: Manually**

Prepare the same context yourself rather than using the prompt generator:

1. **Context preparation only:** Reuse the approved reference hash from [step 4.2, Option B, item 1](#42-prove-manual-retrieval), or recalculate it from the approved original package on the workstation. Do not use an unverified VM hash. Privately construct the approved VM resource ID using your verified subscription, lab RG and VM:

   ```text
   /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<LAB_RG>/providers/Microsoft.Compute/virtualMachines/<VM_NAME>
   ```

2. **Agent execution, not workstation execution:** Open a new conversation with the correct SRE Agent in Review mode. Supply the exact resource ID, current reader hash, fixed source `C:\SP-SRE-Lab\Synthetic-ULS.log`, fixed reader `C:\SP-SRE-Lab\Read-UlsLab.ps1`, and the **complete hash-checked PowerShell payload from step 4.2**, first using the negative GUID `33333333-3333-3333-3333-333333333333`. Replace every placeholder before submission. Submit the payload as agent context; do not run it in workstation PowerShell.
3. Include these instructions alongside that payload:

   ```text
   Investigate only the approved synthetic fixture on the specified nonproduction VM.
   Propose the exact Azure Action Run Command invocation using RunPowerShellScript
   and this payload for administrator approval. Execute only after approval.
   Send the script TEXT as the payload, not a path on my workstation.
   Do not install/change files or permissions, restart services, enumerate other
   machines, remove the hash check, or substitute another reader.
   Do not use RDP, SMB, WinRM, an MCP connector or Log Analytics.
   Report the exact target, actual execution identity if exposed, fresh tool trace,
   stdout and stderr, queryUtc, source, file, correlationId, matchingRecordsReturned,
   partial, coverage and evidence. If execution fails or is unavailable, report the
   error and stop; never invent evidence or substitute a previous/manual result.
   Do not automatically retry a timeout; first have the administrator inspect status.
   Zero matches applies only to this synthetic file, not SharePoint/farm health.
   ```

4. Follow [Approve and verify execution](./SRE-Agent-Testing.md#approve-and-verify-execution): inspect the exact proposed target/payload, approve only that action, and inspect actual tool stdout/stderr. Require zero matches, empty evidence and `partial = false` for this negative control.
5. Request the positive GUID `11111111-1111-1111-1111-111111111111`, require a fresh hash-checked payload for it, review/approve again, and require exactly two evidence records with `partial = false`. Do not accept the previous call's output for this new request.
6. Record whether execution used the intended UAMI or OBO; if identity is not exposed, leave that gate open. Do not grant broader permissions to resolve missing context or tool configuration.

Both options share the [authoritative test acceptance procedure](./SRE-Agent-Testing.md); they differ only in context preparation. Review mode governs Azure infrastructure approvals, not a read-only execution sandbox. [Run modes](https://learn.microsoft.com/azure/sre-agent/run-modes).

**Checkpoint:** Actual agent calls return the expected positive/negative evidence. Manual reads, generated prompts and expected answers are not substitutes.

## 7. Verify completion and clean up

### Acceptance gates and evidence

**Option A: Using scripts**

The package has no script that certifies end-to-end agent acceptance. [Test-Lab.ps1](../scripts/Test-Lab.ps1) is an operator transport check only. Use Option B even when setup and prompts used scripts.

**Option B: Manually**

**Actions:** Use the [test acceptance checks and status record](./SRE-Agent-Testing.md#approve-and-verify-execution). Record target, execution identity, approved hashes, UTC, tool results and coverage privately.

For both controls, verify a fresh successful agent call, correct VM/file/GUID, no guest errors, expected counts, `partial = false`, evidence line references, and a conclusion limited to the evidence. Keep provisioning, manual transport, agent execution, identity verification and customer acceptance as separate outcomes. Record failures and unknowns explicitly.

**Checkpoint:** Required tests pass with evidence. Cleanup is separately approved and can be deferred while the lab is needed; account for ongoing costs.

### Cleanup

Stop agent requests. Inspect every resource and confirm the group is dedicated/disposable. Never delete shared agents/resources, unregister providers, or treat conversation deletion as guaranteed evidence erasure.

**Option A: Using scripts**

There is no cleanup wrapper; the existing direct Azure CLI commands below are the command-line option. Separate owner approval is required before each destructive action.

For any command-line cleanup or compute pause below, restore the verified target first; do not rely on variables left by another branch or terminal:

```powershell
$subscription = $target.SubscriptionId.ToString()
$rg = $target.ResourceGroupName
$vm = $target.VmName
```

**Portal-created grant:** If you used [step 5.7 Option B](#option-b-manually), do not use the deployment-output commands below for that grant. After separate approval, remove the exact VM assignment through IAM using your privately recorded role/assignment IDs. Delete the custom role only if no remaining assignments use it and deletion is approved. [Custom-role deletion](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#delete-a-custom-role), checked November 16, 2026.

**Script-created grant - RBAC owner:** Review the exact assignment/role output IDs before removing them:

```powershell
$outputs = az deployment group show --subscription $subscription --resource-group $rg `
    --name "$vm-agent-access" --query properties.outputs --output json
if ($LASTEXITCODE -ne 0) { throw 'Cannot retrieve RBAC output IDs; inspect the deployment.' }
$ids = $outputs | ConvertFrom-Json
$ids | ConvertTo-Json -Depth 4
```

Only after confirming these IDs belong to the approved temporary grant:

```powershell
az role assignment delete --subscription $subscription --ids $ids.roleAssignmentId.value
if ($LASTEXITCODE -ne 0) { throw 'Role assignment cleanup failed.' }
az role definition delete --subscription $subscription --name ($ids.roleDefinitionId.value.Split('/')[-1])
if ($LASTEXITCODE -ne 0) { throw 'Role definition cleanup failed; inspect remaining assignments.' }
```

Review inherited/onboarding access separately. To pause **compute only**:

```powershell
az vm deallocate --subscription $subscription --resource-group $rg --name $vm
if ($LASTEXITCODE -ne 0) { throw 'VM deallocation failed.' }
```

For separately approved **full lab deletion**, inspect the scope first, then use Azure CLI's confirmation:

```powershell
az resource list --subscription $subscription --resource-group $rg --output table
if ($LASTEXITCODE -ne 0) { throw 'Cannot verify cleanup scope.' }
az group delete --subscription $subscription --name $rg
if ($LASTEXITCODE -ne 0) { throw 'Resource group cleanup failed; inspect remaining charges.' }
```

**Option B: Manually**

1. Stop further investigations and retain approved evidence privately. Inspect **Azure Portal > lab VM > Access control (IAM) > Role assignments**. Match the precise temporary role, VM scope and agent UAMI to the recorded assignment ID; after approval, remove **only that assignment**. Review inherited/onboarding access separately. [Remove a role assignment](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-remove#azure-portal).
2. In the lab RG's **IAM > Roles**, locate the recorded custom role. Delete it only after confirming no remaining assignments depend on it and receiving approval. A portal-created grant has no Bicep output record; use recorded IDs, not a guessed deployment. [Delete a custom role](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal#delete-a-custom-role).
3. If retaining the lab but pausing compute, open the exact VM and select **Stop**, confirm, wait, and verify **Stopped (deallocated)** rather than merely shutting Windows down inside the VM. This does not delete disks or networking. [VM power states and billing](https://learn.microsoft.com/azure/virtual-machines/states-billing).
4. For separately approved **full lab deletion**, open the dedicated VM lab RG, inspect its complete resource list and dependencies, verify the subscription/name against approval, then select **Delete resource group** and type the exact group name to confirm. Never apply this to an existing SharePoint/shared RG. Do not remove locks or backup protections just to force deletion; ask the owner if blocked. [Resource-group deletion](https://learn.microsoft.com/azure/azure-resource-manager/management/delete-resource-group#delete-resource-group).
5. Wait for removal to complete and verify the intended resources/temporary access are gone. Failed or pending deletion is not completion. Make a separate approved keep/delete decision for the agent RG, identities and monitoring resources; do not delete a shared agent/UAMI.
6. Remove only your approved temporary staging files (`C:\Temp\SP-LabSetup\Initialize-UlsLab.ps1` and `C:\Temp\SP-LabSetup\Read-UlsLab.ps1`) if the VM-local route was used and they are no longer needed. If the text-transfer helper was used, also remove the exact workstation `$transfer` file and VM `C:\Temp\Stage-LabFiles.ps1` after verification. Do not delete the installed fixture while retaining the lab for further tests.

**Checkpoint:** Approved resources/access removed or retained with an owner and budget. Disk/NAT/IP/agent charges can remain after VM deallocation; the separate agent RG requires its own approved decision.

## Troubleshooting

Stop on errors/timeouts and inspect state before retrying. For mistaken correlation-ID/subscription handling, restore the [approved investigation context](./SRE-Agent-Testing.md#supply-context-once).

If manual reads work but the agent fails, check the actual UAMI/OBO identity, VM scope, inherited/deny access, propagation, tool availability and Review approval. Do not fix missing context by granting Contributor or opening inbound ports.

## Moving to actual SharePoint logs

Real ULS support is separate engineering work: approved sanitized samples, schema/encoding/rotation/time filtering, source-side redaction and actual-host permissions. See [Next steps](./Next-Steps.md). Do not point the synthetic reader at production folders.

## Microsoft Learn references


- [Azure CLI interactive authentication](https://learn.microsoft.com/cli/azure/authenticate-azure-cli-interactively).
- [Resource-provider registration](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types#azure-portal), [VM SKU inspection](https://learn.microsoft.com/cli/azure/vm#az-vm-list-skus), [VM image inspection](https://learn.microsoft.com/cli/azure/vm/image#az-vm-image-show), and [quota versus capacity](https://learn.microsoft.com/azure/virtual-machines/quotas).
- [Bicep build](https://learn.microsoft.com/azure/azure-resource-manager/bicep/bicep-cli#build) and [portal ARM-template deployment](https://learn.microsoft.com/azure/azure-resource-manager/templates/deploy-portal).
- [Windows Action Run Command](https://learn.microsoft.com/azure/virtual-machines/windows/run-command): VM Agent prerequisite, SYSTEM execution, permissions, portal parameters and restrictions. This guide uses `RunPowerShellScript` at the specific VM scope, not Managed Run Command resources.
- [Bastion text clipboard](https://learn.microsoft.com/azure/bastion/bastion-vm-copy-paste), [native-client file transfer](https://learn.microsoft.com/azure/bastion/vm-upload-download-native), [native-client configuration](https://learn.microsoft.com/azure/bastion/native-client), [Developer SKU upgrade](https://learn.microsoft.com/azure/bastion/upgrade-sku#upgrade-from-developer-sku), and [Set-Clipboard](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/set-clipboard). The two-file text-staging helper is a proposed package implementation, not a Microsoft-provided file-upload feature.
- [Create SRE Agent](https://learn.microsoft.com/azure/sre-agent/create-and-set-up), [agent identity](https://learn.microsoft.com/azure/sre-agent/agent-identity), [managed resources](https://learn.microsoft.com/azure/sre-agent/manage-permissions), and [run modes](https://learn.microsoft.com/azure/sre-agent/run-modes).
- [SRE Agent user roles](https://learn.microsoft.com/azure/sre-agent/user-roles) and [agent permissions/OBO](https://learn.microsoft.com/azure/sre-agent/permissions): human authority, resource permissions and delegated execution are distinct.
- [Azure CLI Action Run Command](https://learn.microsoft.com/cli/azure/vm/run-command#az-vm-run-command-invoke) and [Compute Action Run Command REST API, version 2024-07-01](https://learn.microsoft.com/en-us/rest/api/compute/virtual-machines/run-command?view=rest-compute-2024-07-01): script-input contract, not proof of this agent tool's executor behavior.
- [Portal custom roles](https://learn.microsoft.com/azure/role-based-access-control/custom-roles-portal), [portal role assignment](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-portal), and [role removal](https://learn.microsoft.com/azure/role-based-access-control/role-assignments-remove#azure-portal).
- [VM states/billing](https://learn.microsoft.com/azure/virtual-machines/states-billing) and [resource-group deletion](https://learn.microsoft.com/azure/azure-resource-manager/management/delete-resource-group).

The manual deployment retains the package's `Microsoft.Compute/virtualMachines@2024-07-01` and network resources at `@2024-05-01` from [main.bicep](../infra/main.bicep). Portal/CLI service calls choose their own supported API versions; this guide does not prescribe or infer those versions.
